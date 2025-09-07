package `in`.drdna.ledfx

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Bundle
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    private val METHOD_CHANNEL = "system_audio_recorder/methods"
    private val EVENT_CHANNEL = "system_audio_recorder/events"

    private lateinit var projectionManager: MediaProjectionManager
    private lateinit var projectionLauncher: ActivityResultLauncher<Intent>
    private var pendingResult: MethodChannel.Result? = null
    private var lastResultCode = 0
    private var lastResultData: Intent? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        projectionManager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager

        projectionLauncher =
            registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
                if (result.resultCode == Activity.RESULT_OK && result.data != null) {
                    lastResultCode = result.resultCode
                    lastResultData = result.data
                    pendingResult?.success(true)
                } else {
                    pendingResult?.success(false)
                }
                pendingResult = null
            }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) { 
        super.configureFlutterEngine(flutterEngine)

        // Pass method + event channels to RecordingBridge
        val methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
        val eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
        RecordingBridge.setup(methodChannel, eventChannel)

        // Handle actual service lifecycle calls from Flutter
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestProjection" -> {
                    pendingResult = result
                    val intent = projectionManager.createScreenCaptureIntent()
                    projectionLauncher.launch(intent)
                }
                "startRecording" -> {
                    if (lastResultData != null) {
                        val svc = Intent(this, RecordingService::class.java).apply {
                            action = RecordingService.ACTION_START
                            putExtra(RecordingService.EXTRA_RESULT_CODE, lastResultCode)
                            putExtra(RecordingService.EXTRA_RESULT_DATA, lastResultData)
                        }
                        startForegroundService(svc)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "stopRecording" -> {
                    val svc = Intent(this, RecordingService::class.java).apply {
                        action = RecordingService.ACTION_STOP
                    }
                    startService(svc)
                    result.success(null)
                }
                "pauseRecording" -> {
                    val svc = Intent(this, RecordingService::class.java).apply {
                        action = RecordingService.ACTION_PAUSE
                    }
                    startService(svc)
                    result.success(null)
                }
                "resumeRecording" -> {
                    val svc = Intent(this, RecordingService::class.java).apply {
                        action = RecordingService.ACTION_RESUME
                    }
                    startService(svc)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
