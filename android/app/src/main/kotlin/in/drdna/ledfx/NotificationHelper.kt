package `in`.drdna.ledfx

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

object NotificationHelper {
        const val CHANNEL_ID = "rec_channel"
        const val NOTIF_ID = 96

        fun buildNotification(context: Context, isRecording: Boolean): Notification {
                val state =
                        when {
                                isRecording -> "Recording"
                                else -> "Idle"
                        }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val chan =
                                NotificationChannel(
                                                CHANNEL_ID,
                                                "Recording",
                                                NotificationManager
                                                        .IMPORTANCE_HIGH // Max importance
                                        )
                                        .apply {
                                                // setShowBadge(false)
                                                description = "System audio recording"
                                                setSound(null, null) // optional: no sound
                                                lockscreenVisibility =
                                                        Notification.VISIBILITY_PUBLIC
                                        }

                        (context.getSystemService(Context.NOTIFICATION_SERVICE) as
                                        NotificationManager)
                                .createNotificationChannel(chan)
                }
                // Intent to open app UI on tap
                val launchIntent =
                        Intent(context, MainActivity::class.java).apply {
                                flags =
                                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                                                Intent.FLAG_ACTIVITY_CLEAR_TOP
                        }
                val pendingLaunch =
                        PendingIntent.getActivity(
                                context,
                                0,
                                launchIntent,
                                PendingIntent.FLAG_UPDATE_CURRENT or
                                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                                                PendingIntent.FLAG_MUTABLE
                                        else 0
                        )

                // TODO:: Check: Double Implementation
                // // Pause action
                // val pauseIntent =
                //         Intent(context, RecordingService::class.java).apply {
                //             action =
                //                     if (isPaused) RecordingService.ACTION_RESUME
                //                     else RecordingService.ACTION_PAUSE
                //         }
                // val pendingPause =
                //         PendingIntent.getService(
                //                 context,
                //                 1,
                //                 pauseIntent,
                //                 PendingIntent.FLAG_UPDATE_CURRENT or
                //                         if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                //                                 PendingIntent.FLAG_MUTABLE
                //                         else 0
                //         )

                // Stop button
                val stopIntent =
                        Intent(context, RecordingService::class.java).apply {
                                action = RecordingService.ACTION_STOP
                        }
                val stopPending =
                        PendingIntent.getService(
                                context,
                                0,
                                stopIntent,
                                PendingIntent.FLAG_IMMUTABLE
                        )

                val deleteIntent =
                        PendingIntent.getBroadcast(
                                context,
                                0,
                                Intent(context, NotificationDismissReceiver::class.java),
                                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                        )
                var builder =
                        NotificationCompat.Builder(context, CHANNEL_ID)
                                .setContentTitle("System Audio")
                                .setContentText("Status: $state")
                                .setSmallIcon(android.R.drawable.ic_btn_speak_now)
                                .setOngoing(true) // Cannot be swiped away
                                .setPriority(NotificationCompat.PRIORITY_MAX)
                                .setCategory("android.category.RECORDING")
                                .setOnlyAlertOnce(true) // only alert once
                                .setDeleteIntent(deleteIntent)
                                .setContentIntent(pendingLaunch) // tap to open app
                                // .addAction(
                                //         if (isPaused) android.R.drawable.ic_media_play
                                //         else android.R.drawable.ic_media_pause,
                                //         if (isPaused) "Resume" else "Pause",
                                //         pendingPause
                                // )
                                .addAction(android.R.drawable.ic_media_pause, "Stop", stopPending)

                // Pause/Resume button
                //        if (isRecording) {
                //            val pauseIntent =
                //                    Intent(context, RecordingService::class.java).apply {
                //                        action = RecordingService.ACTION_PAUSE
                //                    }
                //            val pausePending =
                //                    PendingIntent.getService(context, 1, pauseIntent,
                // PendingIntent.FLAG_IMMUTABLE)
                //            builder.addAction(android.R.drawable.ic_media_pause, "Pause",
                // pausePending)
                //        } else if (isPaused) {
                //            val resumeIntent =
                //                    Intent(context, RecordingService::class.java).apply {
                //                        action = RecordingService.ACTION_RESUME
                //                    }
                //            val resumePending =
                //                    PendingIntent.getService(context, 2, resumeIntent,
                // PendingIntent.FLAG_IMMUTABLE)
                //            builder.addAction(android.R.drawable.ic_media_play, "Resume",
                // resumePending)
                //        }

                var notification = builder.build()

                notification.flags =
                        notification.flags or
                                Notification.FLAG_ONGOING_EVENT or
                                Notification.FLAG_NO_CLEAR

                return notification
        }

        fun updateNotification(context: Context, isRecording: Boolean) {
                val nm =
                        context.getSystemService(Context.NOTIFICATION_SERVICE) as
                                NotificationManager
                nm.notify(NOTIF_ID, buildNotification(context, isRecording))
        }
}

class NotificationDismissReceiver : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
                // if (intent?.action == "in.drdna.ledfx.NOTIF_DISMISSED") {
                val svcRunning = RecordingService.isRecording
                if (svcRunning && context != null) {
                        val svcIntent = Intent(context, RecordingService::class.java)
                        svcIntent.action = RecordingService.ACTION_UPDATE_NOTIFICATION
                        context.startForegroundService(svcIntent)
                }
                // }
        }
}
