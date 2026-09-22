package no.osilion.agentkhata

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterFragmentActivity() {
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        Channels.register(this, messenger)

        /*
         * The UI engine announces itself here. While it listens, a capture
         * wakes it instead of starting a background engine; the message
         * itself is already on disk and is read from the queue either way.
         */
        EventChannel(messenger, "no.osilion.agentkhata/messages").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                MessageQueue.uiWake = { main.post { events.success(true) } }
                // The UI is authoritative from here; a background engine left
                // running would only compete with it for the same queue.
                BackgroundEngine.shutdown()
            }
            override fun onCancel(arguments: Any?) { MessageQueue.uiWake = null }
        })
    }

    override fun onDestroy() {
        MessageQueue.uiWake = null
        super.onDestroy()
    }
}
