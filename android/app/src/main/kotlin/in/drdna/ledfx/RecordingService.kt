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

    companion object {
        var isRecording = false
        const val ACTION_START = "in.drdna.ledfx.ACTION_START"
        const val ACTION_STOP = "in.drdna.ledfx.ACTION_STOP"
        const val ACTION_UPDATE_NOTIFICATION = "in.drdna.ledfx.ACTION_UPDATE_NOTIFICATION"
        const val EXTRA_RESULT_CODE = "extra_result_code"
        const val EXTRA_RESULT_DATA = "extra_result_data"
        const val EXTRA_CAPTURE_TYPE = "extra_capture_type" // capture or loopback
        const val EXTRA_CHANNELS = "extra_channels" // 1 or 2
        const val EXTRA_SAMPLE_RATE = "extra_sample_rate" // 44100, 48000 etc
        const val EXTRA_BLOCK_SIZE = "extra_block_size" // number of samples to send per event
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val captureType = intent.getStringExtra(EXTRA_CAPTURE_TYPE) ?: "loopback"
                val channels = intent.getIntExtra(EXTRA_CHANNELS, 2)
                val sampleRate = intent.getIntExtra(EXTRA_SAMPLE_RATE, 44100)
                val blockSize = intent.getIntExtra(EXTRA_BLOCK_SIZE, 1024)
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
                        )
                )
                isRecording = true
                if (captureType == "loopback") {
                    startLoopbackRecording(rc, data, channels, sampleRate, blockSize)
                } else {
                    startMicRecording(channels, sampleRate, blockSize)
                }
                RecordingBridge.sendState("recordingStarted")
            }
            ACTION_STOP -> {
                stopCapture()
                isRecording = false
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    stopForeground(Service.STOP_FOREGROUND_REMOVE)
                } else {
                    @Suppress("DEPRECATION") stopForeground(true)
                }
                stopSelf()
                RecordingBridge.sendState("recordingStopped")
            }
            ACTION_UPDATE_NOTIFICATION -> {
                NotificationHelper.updateNotification(
                        this,
                        isRecording = isRecording,
                )
            }
        }
        return START_STICKY
    }

    private fun startLoopbackRecording(
            resultCode: Int,
            resultData: Intent?,
            numChannels: Int,
            sampleRate: Int,
            blockSize: Int
    ) {
        if (captureJob?.isActive == true) return
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
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start projection: ${e.message}")
            RecordingBridge.sendError("projection_failed")
        }

        isRecording = true
        captureJob =
                launch(Dispatchers.IO) {
                    try {
                        val config =
                                AudioPlaybackCaptureConfiguration.Builder(mediaProjection!!)
                                        .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
                                        .addMatchingUsage(AudioAttributes.USAGE_GAME)
                                        .build()

                        val channelMask =
                                if (numChannels == 2) AudioFormat.CHANNEL_IN_STEREO
                                else AudioFormat.CHANNEL_IN_MONO

                        val audioFormat =
                                AudioFormat.Builder()
                                        .setEncoding(AudioFormat.ENCODING_PCM_FLOAT)
                                        .setSampleRate(sampleRate)
                                        .setChannelMask(channelMask)
                                        .build()

                        val minBuf =
                                AudioRecord.getMinBufferSize(
                                                sampleRate,
                                                channelMask,
                                                AudioFormat.ENCODING_PCM_FLOAT
                                        )
                                        .coerceAtLeast(blockSize * numChannels * 4)

                        audioRecord =
                                AudioRecord.Builder()
                                        .setAudioPlaybackCaptureConfig(config)
                                        .setAudioFormat(audioFormat)
                                        .setBufferSizeInBytes(minBuf)
                                        .build()

                        if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                            RecordingBridge.sendError("audio_init_failed")
                            Log.e(TAG, "Loopback AudioRecord init failed")
                            return@launch
                        }

                        audioRecord!!.startRecording()
                        Log.i(TAG, "Loopback recording started")

                        val accumulator = ArrayDeque<Double>()
                        val tempBuffer = FloatArray(blockSize * numChannels)

                        while (isRecording && isActive) {
                            val readCount =
                                    audioRecord!!.read(
                                            tempBuffer,
                                            0,
                                            tempBuffer.size,
                                            AudioRecord.READ_BLOCKING
                                    )
                            if (readCount > 0) {
                                if (numChannels == 2) {
                                    for (i in 0 until readCount step 2) {
                                        val mono =
                                                ((tempBuffer[i] + tempBuffer[i + 1]) * 0.5)
                                                        .toDouble()
                                        accumulator.add(mono)
                                    }
                                } else {
                                    for (i in 0 until readCount) {
                                        accumulator.add(tempBuffer[i].toDouble())
                                    }
                                }

                                while (accumulator.size >= blockSize) {
                                    val out = ArrayList<Double>(blockSize)
                                    repeat(blockSize) { out.add(accumulator.removeFirst()) }

                                    withContext(Dispatchers.Main) { RecordingBridge.sendAudio(out) }
                                }
                            }
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Loopback error: ${e.message}", e)
                        withContext(Dispatchers.Main) {
                            RecordingBridge.sendError("loopback_failed")
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

    private fun startMicRecording(numChannels: Int, sampleRate: Int, blockSize: Int) {
        if (captureJob?.isActive == true) return

        captureJob =
                launch(Dispatchers.IO) {
                    try {
                        val channelMask =
                                if (numChannels == 2) AudioFormat.CHANNEL_IN_STEREO
                                else AudioFormat.CHANNEL_IN_MONO

                        val audioFormat =
                                AudioFormat.Builder()
                                        .setEncoding(AudioFormat.ENCODING_PCM_FLOAT)
                                        .setSampleRate(sampleRate)
                                        .setChannelMask(channelMask)
                                        .build()

                        val minBuf =
                                AudioRecord.getMinBufferSize(
                                                sampleRate,
                                                channelMask,
                                                AudioFormat.ENCODING_PCM_FLOAT
                                        )
                                        .coerceAtLeast(blockSize * numChannels * 4)

                        audioRecord =
                                AudioRecord.Builder()
                                        .setAudioSource(MediaRecorder.AudioSource.MIC)
                                        .setAudioFormat(audioFormat)
                                        .setBufferSizeInBytes(minBuf)
                                        .build()

                        if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                            RecordingBridge.sendError("audio_init_failed")
                            Log.e(TAG, "Mic AudioRecord init failed")
                            return@launch
                        }

                        audioRecord!!.startRecording()
                        Log.i(TAG, "Mic recording started")

                        val accumulator = ArrayDeque<Double>()
                        val tempBuffer = FloatArray(blockSize * numChannels)

                        while (isRecording && isActive) {
                            val readCount =
                                    audioRecord!!.read(
                                            tempBuffer,
                                            0,
                                            tempBuffer.size,
                                            AudioRecord.READ_BLOCKING
                                    )
                            if (readCount > 0) {
                                if (numChannels == 2) {
                                    for (i in 0 until readCount step 2) {
                                        val mono =
                                                ((tempBuffer[i] + tempBuffer[i + 1]) * 0.5)
                                                        .toDouble()
                                        accumulator.add(mono)
                                    }
                                } else {
                                    for (i in 0 until readCount) {
                                        accumulator.add(tempBuffer[i].toDouble())
                                    }
                                }

                                while (accumulator.size >= blockSize) {
                                    val out = ArrayList<Double>(blockSize)
                                    repeat(blockSize) { out.add(accumulator.removeFirst()) }

                                    withContext(Dispatchers.Main) { RecordingBridge.sendAudio(out) }
                                }
                            }
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Mic error: ${e.message}", e)
                        withContext(Dispatchers.Main) { RecordingBridge.sendError("mic_failed") }
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
        isRecording = false

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
