package no.osilion.agentkhata

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * A headless Flutter engine that runs the capture pipeline with the app closed.
 *
 * ## Why this has to exist
 *
 * The notification listener is a system service: Android keeps it bound, and
 * restarts the process to deliver to it, whether or not anyone has opened the
 * app today. But parsing, commission and sync are Dart — one implementation,
 * tested, shared with the UI — and Dart only runs inside a Flutter engine.
 * Without this, a transaction captured while the app was swiped away sat in
 * the native queue until somebody opened the app, and "it lands in the portal
 * by itself" was true only for agents who never close anything.
 *
 * ## Lifecycle
 *
 * Started on the first capture that finds no UI engine listening. Runs
 * `backgroundMain` in lib/main.dart, which processes the queue and syncs.
 * Every later capture pokes it through the `background` channel. After a few
 * idle minutes it is destroyed; the next capture starts a fresh one. Starting
 * an engine costs a few hundred milliseconds — nothing, next to a sale.
 *
 * All engine work happens on the main looper, which is where Flutter requires
 * it and where both the listener and the SMS receiver are called anyway.
 */
object BackgroundEngine {
    private const val TAG = "AgentKhataBg"
    private const val IDLE_MS = 3 * 60_000L

    private val main = Handler(Looper.getMainLooper())
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private val stopWhenIdle = Runnable { shutdown() }

    fun kick(context: Context) {
        val app = context.applicationContext
        main.post {
            // The UI engine took over while this was queued; it will process.
            if (MessageQueue.uiWake != null) return@post
            try {
                if (engine == null) start(app) else channel?.invokeMethod("process", null)
            } catch (error: Throwable) {
                // Never let capture crash the listener: the message is already
                // on disk and the next open of the app processes it.
                Log.e(TAG, "background engine failed to start", error)
                shutdown()
            }
            main.removeCallbacks(stopWhenIdle)
            main.postDelayed(stopWhenIdle, IDLE_MS)
        }
    }

    private fun start(context: Context) {
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(context)
        loader.ensureInitializationComplete(context, null)

        // Registers every plugin, as the UI engine does, so drift, secure
        // storage and http work identically in here.
        val created = FlutterEngine(context)
        val messenger = created.dartExecutor.binaryMessenger
        Channels.register(context, messenger)
        channel = MethodChannel(messenger, "no.osilion.agentkhata/background")

        created.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "backgroundMain"),
        )
        engine = created
        Log.i(TAG, "background engine started")
    }

    fun shutdown() {
        main.removeCallbacks(stopWhenIdle)
        engine?.destroy()
        engine = null
        channel = null
    }
}
