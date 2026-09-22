package no.osilion.agentkhata

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * The control channel, registered identically on the UI engine and the
 * background engine, so the Dart that processes the queue and syncs is the
 * same code wherever it runs.
 *
 * Health questions are answered here rather than through plugins: they are
 * one system call each, and every plugin added is another thing that must
 * work inside a headless engine.
 */
object Channels {
    const val CONTROL = "no.osilion.agentkhata/control"

    fun register(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        MethodChannel(messenger, CONTROL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "isNotificationAccessGranted" -> result.success(notificationAccess(app))
                    "openNotificationAccessSettings" -> {
                        app.startActivity(
                            Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                        )
                        result.success(null)
                    }
                    "peekQueue" -> result.success(MessageQueue.peek(app))
                    "ackQueue" -> {
                        @Suppress("UNCHECKED_CAST")
                        val ids = (call.argument<List<String>>("ids") ?: emptyList())
                        MessageQueue.ack(app, ids)
                        result.success(null)
                    }
                    "tryLock" -> result.success(
                        EngineLock.tryAcquire(
                            call.argument<String>("name") ?: "default",
                            (call.argument<Number>("leaseMs") ?: 60_000).toLong(),
                        ),
                    )
                    "unlock" -> {
                        EngineLock.release(call.argument<String>("name") ?: "default")
                        result.success(null)
                    }
                    "health" -> result.success(health(app))
                    "device" -> result.success(device(app))
                    "installedOperatorApps" -> result.success(installedOperatorApps(app))
                    "requestBatteryUnrestricted" -> result.success(requestBatteryUnrestricted(app))
                    "openAutostartSettings" -> result.success(openAutostartSettings(app))
                    "openAppDetails" -> {
                        app.startActivity(
                            android.content.Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, android.net.Uri.fromParts("package", app.packageName, null))
                                .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK),
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Throwable) {
                result.error("native", error.message, null)
            }
        }
    }

    private fun notificationAccess(context: Context): Boolean {
        val flat = Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners") ?: ""
        val me = ComponentName(context, OperatorNotificationListener::class.java).flattenToString()
        return flat.split(":").any { it == me }
    }

    private fun batteryUnrestricted(context: Context): Boolean {
        val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return power.isIgnoringBatteryOptimizations(context.packageName)
    }

    private fun health(context: Context): Map<String, Any?> = mapOf(
        "notificationAccess" to notificationAccess(context),
        "smsAccess" to (context.checkSelfPermission(Manifest.permission.RECEIVE_SMS) ==
            PackageManager.PERMISSION_GRANTED),
        "batteryUnrestricted" to batteryUnrestricted(context),
        "queued" to MessageQueue.size(context),
        "lastCaptureAt" to MessageQueue.lastCaptureAt(context).takeIf { it > 0 },
        "sdk" to Build.VERSION.SDK_INT,
        "manufacturer" to Build.MANUFACTURER,
        "restrictedSettings" to restrictedSettingsBlocked(context),
    )

    /**
     * Android 13+ greys out notification access and SMS for an app installed
     * from a file rather than a store, until the person taps "Allow restricted
     * settings" in App info. There is no API to ask for it; the app can only
     * notice it and walk the person there. The app-op reads back what they
     * chose, so the guide disappears once it is done.
     */
    private val STORES = setOf(
        "com.android.vending", "com.sec.android.app.samsungapps", "com.xiaomi.market", "com.xiaomi.mipicks",
        "com.huawei.appmarket", "com.heytap.market", "com.oppo.market", "com.vivo.appstore", "com.transsion.phoenix",
    )

    private fun restrictedSettingsBlocked(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < 33) return false
        val installer = try {
            context.packageManager.getInstallSourceInfo(context.packageName).installingPackageName
        } catch (_: Throwable) { null }
        // Stores are trusted; a cable install (adb) has no installer and is
        // not restricted either. Only a file opened from a browser, chat app
        // or file manager goes through the package installer and gets blocked.
        if (installer == null || installer in STORES) return false
        return try {
            val ops = context.getSystemService(Context.APP_OPS_SERVICE) as android.app.AppOpsManager
            val mode = ops.unsafeCheckOpNoThrow("android:access_restricted_settings", context.applicationInfo.uid, context.packageName)
            mode != android.app.AppOpsManager.MODE_ALLOWED
        } catch (_: Throwable) {
            // The op name is not public API; if a phone lacks it, assume the
            // block is there only while notification access is still off.
            !notificationAccess(context)
        }
    }

    private fun device(context: Context): Map<String, Any?> {
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        val brand = Build.MANUFACTURER.replaceFirstChar { it.uppercase() }
        val model = if (Build.MODEL.startsWith(brand, ignoreCase = true)) Build.MODEL else "$brand ${Build.MODEL}"
        return mapOf("model" to model, "appVersion" to (info.versionName ?: "?"))
    }

    /**
     * Which operator apps this phone has — the basis for pre-ticking "this
     * phone captures bKash and Nagad" so a joining phone needs no explaining.
     * Needs the `<queries>` block in the manifest on Android 11 and later.
     */
    private fun installedOperatorApps(context: Context): List<String> =
        OperatorNotificationListener.PACKAGES.filter { pkg ->
            try {
                context.packageManager.getPackageInfo(pkg, 0)
                true
            } catch (_: PackageManager.NameNotFoundException) {
                false
            }
        }

    /**
     * Ask to be left alone by battery optimisation.
     *
     * On the phones agents actually carry — Tecno, Infinix, Xiaomi, Oppo,
     * Realme, Vivo — an app that is not exempt has its listener stopped within
     * hours, and capture fails silently until someone opens the app. This is
     * the single most important permission after notification access.
     */
    private fun requestBatteryUnrestricted(context: Context): Boolean {
        if (batteryUnrestricted(context)) return true
        val direct = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
            .setData(Uri.parse("package:${context.packageName}"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            context.startActivity(direct)
            true
        } catch (_: Throwable) {
            context.startActivity(
                Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            true
        }
    }

    /**
     * The manufacturers' own "auto start" screens, which sit on top of
     * Android's battery settings and default to killing everything. None of
     * them are public API, so this tries each known screen and opens the first
     * that exists; false means this phone has none of them and needs nothing.
     */
    private fun openAutostartSettings(context: Context): Boolean {
        val candidates = listOf(
            ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity"),
            ComponentName("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity"),
            ComponentName("com.oppo.safe", "com.oppo.safe.permission.startup.StartupAppListActivity"),
            ComponentName("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"),
            ComponentName("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity"),
            ComponentName("com.transsion.phonemaster", "com.itel.autobootmanager.activity.AutoBootMgrActivity"),
            ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"),
            ComponentName("com.samsung.android.lool", "com.samsung.android.sm.battery.ui.BatteryActivity"),
        )
        for (component in candidates) {
            val intent = Intent().setComponent(component).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (context.packageManager.resolveActivity(intent, 0) != null) {
                return try {
                    context.startActivity(intent)
                    true
                } catch (_: Throwable) {
                    false
                }
            }
        }
        return false
    }
}
