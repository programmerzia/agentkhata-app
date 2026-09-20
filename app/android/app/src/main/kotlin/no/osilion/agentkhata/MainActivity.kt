package no.osilion.agentkhata

import android.content.ComponentName
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        EventChannel(messenger, "no.osilion.agentkhata/messages").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                MessageQueue.liveSink = { msg -> main.post { events.success(msg) } }
            }
            override fun onCancel(arguments: Any?) { MessageQueue.liveSink = null }
        })

        MethodChannel(messenger, "no.osilion.agentkhata/control").setMethodCallHandler { call, result ->
            when (call.method) {
                "isNotificationAccessGranted" -> {
                    val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: ""
                    val me = ComponentName(this, OperatorNotificationListener::class.java).flattenToString()
                    result.success(flat.split(":").any { it == me || it.contains(packageName) })
                }
                "openNotificationAccessSettings" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(null)
                }
                "drainQueue" -> result.success(MessageQueue.drain(applicationContext))
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        MessageQueue.liveSink = null
        super.onDestroy()
    }
}
