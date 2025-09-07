package `in`.drdna.ledfx

import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

object RecordingBridge {
    private var eventSink: EventChannel.EventSink? = null

    fun setup(methodChannel: MethodChannel, eventChannel: EventChannel) {
        // methodChannel.setMethodCallHandler { call, result ->
        //     when (call.method) {
        //         "start" -> result.success(null)
        //         "stop" -> result.success(null)
        //         "pause" -> result.success(null)
        //         "resume" -> result.success(null)
        //         else -> result.notImplemented()
        //     }
        // }
        
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }
            override fun onCancel(args: Any?) {
                eventSink = null
            }
        })
    }

    // ===== Helpers to send events back to Flutter =====

    fun sendAudio(bytes: ByteArray) {
        eventSink?.success(mapOf("type" to "audio", "data" to bytes))
    }

    fun sendState(state: String) {
        // state = "started", "paused", "resumed", "stopped"
        eventSink?.success(mapOf("type" to "state", "value" to state))
    }

    fun sendError(message: String) {
        eventSink?.success(mapOf("type" to "error", "message" to message))
    }
}
