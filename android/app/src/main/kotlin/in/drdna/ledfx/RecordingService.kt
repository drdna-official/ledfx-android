package `in`.drdna.ledfx

import android.app.Service
import android.content.Intent
import android.media.*
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.IBinder
import android.util.Log
import kotlinx.coroutines.*

class RecordingService : Service(), CoroutineScope by MainScope() {
    private val TAG = "RecordingService"

    private var audioRecord: AudioRecord? = null
    private var mediaProjection: MediaProjection? = null
    private var captureJob: Job? = null
    private var isPaused = false

    companion object {
        var isRunning = false
        const val ACTION_START = "in.drdna.ledfx.ACTION_START"
        const val ACTION_STOP = "in.drdna.ledfx.ACTION_STOP"
        const val ACTION_PAUSE = "in.drdna.ledfx.ACTION_PAUSE"
        const val ACTION_RESUME = "in.drdna.ledfx.ACTION_RESUME"
        const val ACTION_UPDATE_NOTIFICATION = "in.drdna.ledfx.ACTION_UPDATE_NOTIFICATION"
        const val EXTRA_RESULT_CODE = "extra_result_code"
        const val EXTRA_RESULT_DATA = "extra_result_data"
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val rc = intent.getIntExtra(EXTRA_RESULT_CODE, 0)
                val data =
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            intent.getParcelableExtra(EXTRA_RESULT_DATA, Intent::class.java)
                        } else {
                            @Suppress("DEPRECATION") intent.getParcelableExtra(EXTRA_RESULT_DATA)
                        }

                // Start foreground service with notification immediately
                startForeground(
                        NotificationHelper.NOTIF_ID,
                        NotificationHelper.buildNotification(
                                this,
                                isRecording = true,
                                isPaused = false
                        )
                )
                isRunning = true
                startCaptureSafely(rc, data)
                RecordingBridge.sendState("recordingStarted")

            }
            ACTION_STOP -> {
                stopCapture()
                isRunning = false
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    stopForeground(Service.STOP_FOREGROUND_REMOVE)
                } else {
                    @Suppress("DEPRECATION") stopForeground(true)
                }
                stopSelf()
                RecordingBridge.sendState("recordingStopped")

            }
            ACTION_PAUSE -> {
                isPaused = true
                NotificationHelper.updateNotification(this, isRecording = false, isPaused = true)
                RecordingBridge.sendState("recordingPaused")

            }
            ACTION_RESUME -> {
                isPaused = false
                NotificationHelper.updateNotification(this, isRecording = true, isPaused = false)
                RecordingBridge.sendState("recordingResumed")
            }
            ACTION_UPDATE_NOTIFICATION -> {
                NotificationHelper.updateNotification(
                        this,
                        isRecording = !isPaused,
                        isPaused = isPaused
                )
            }
        }
        return START_STICKY
    }

    private fun startCaptureSafely(resultCode: Int, resultData: Intent?) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            Log.e(TAG, "AudioPlaybackCapture requires Android Q+")
            RecordingBridge.sendError("not_supported")
            return
        }
        if (resultData == null) {
            Log.e(TAG, "No MediaProjection permission data supplied")
            RecordingBridge.sendError("permission_denied")
            return
        }
        try {
            val mpm = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            mediaProjection = mpm.getMediaProjection(resultCode, resultData)
            startCaptureLoop()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start projection: ${e.message}")
            RecordingBridge.sendError("projection_failed")
        }
    }

    private fun startCaptureLoop() {
        if (captureJob?.isActive == true) return

        val sampleRate = 44100
        val channelMask = AudioFormat.CHANNEL_IN_STEREO
        val audioFormat =
                AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(sampleRate)
                        .setChannelMask(channelMask)
                        .build()

        val config =
                AudioPlaybackCaptureConfiguration.Builder(mediaProjection!!)
                        .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
                        .addMatchingUsage(AudioAttributes.USAGE_GAME)
                        .addMatchingUsage(AudioAttributes.USAGE_ASSISTANCE_ACCESSIBILITY)
                        .build()

        val minBuf =
                AudioRecord.getMinBufferSize(
                                sampleRate,
                                channelMask,
                                AudioFormat.ENCODING_PCM_16BIT
                        )
                        .coerceAtLeast(8192)

        audioRecord =
                AudioRecord.Builder()
                        .setAudioFormat(audioFormat)
                        .setBufferSizeInBytes(minBuf)
                        .setAudioPlaybackCaptureConfig(config)
                        .build()

        if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
            RecordingBridge.sendError("audio_init_failed")
            Log.e(TAG, "AudioRecord not initialized")
            return
        }

        captureJob =
                launch(Dispatchers.IO) {
                    try {
                        try {
                            audioRecord?.startRecording()
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) {
                                RecordingBridge.sendError("record_start_failed")
                            }
                            return@launch
                        }

                        val buffer = ByteArray(minBuf)
                        while (isActive) {
                            if (isPaused) {
                                delay(50)
                                continue
                            }
                            val read = audioRecord?.read(buffer, 0, buffer.size) ?: -1
                            if (read > 0) {
                                val copy = buffer.copyOf(read)
                                withContext(Dispatchers.Main) {
                                    RecordingBridge.sendAudio(copy)
                                }
                            } else {
                                delay(5)
                            }
                        }
                    } catch (ex: Exception) {
                        Log.e(TAG, "Capture loop error: ${ex.localizedMessage}")
                        withContext(Dispatchers.Main) {
                            RecordingBridge.sendError("capture_failed")
                        }
                    } finally {
                        try {
                            audioRecord?.stop()
                        } catch (_: Throwable) {}
                        try {
                            audioRecord?.release()
                        } catch (_: Throwable) {}
                    }
                }
    }

    private fun stopCapture() {
        captureJob?.cancel()
        captureJob = null
        try {
            audioRecord?.stop()
        } catch (_: Throwable) {}
        try {
            audioRecord?.release()
        } catch (_: Throwable) {}
        audioRecord = null
        mediaProjection?.stop()
        mediaProjection = null
    }

    override fun onDestroy() {
        stopCapture()
        cancel()
        super.onDestroy()
    }
}
