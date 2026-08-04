package com.example.dex.network

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.example.dex.R

class NotificationHelper(private val context: Context) {

    private val channelId = "dex_service_channel"

    init {
        createChannel()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                context.getString(R.string.notif_channel_bg),
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = context.getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    fun getForegroundServiceNotification(): Notification {
        return NotificationCompat.Builder(context, channelId)
            .setContentTitle(context.getString(R.string.notif_bg_title))
            .setContentText(context.getString(R.string.notif_bg_desc))
            .setSmallIcon(android.R.drawable.ic_menu_share)
            .build()
    }

    fun showIncomingFileNotification(sessionId: String, notificationId: Int, fileCount: Int) {
        val acceptIntent = Intent(context, FileTransferReceiver::class.java).apply {
            action = "com.example.dex.ACCEPT_TRANSFER"
            putExtra("SESSION_ID", sessionId)
            putExtra("NOTIFICATION_ID", notificationId)
        }

        val rejectIntent = Intent(context, FileTransferReceiver::class.java).apply {
            action = "com.example.dex.REJECT_TRANSFER"
            putExtra("SESSION_ID", sessionId)
            putExtra("NOTIFICATION_ID", notificationId)
        }

        val acceptPendingIntent = PendingIntent.getBroadcast(
            context, notificationId, acceptIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val rejectPendingIntent = PendingIntent.getBroadcast(
            context, notificationId + 1, rejectIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, channelId)
            .setContentTitle(context.getString(R.string.notif_incoming_title))
            .setContentText(context.getString(R.string.notif_incoming_desc, fileCount))
            .setSmallIcon(android.R.drawable.ic_menu_share)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .addAction(android.R.drawable.ic_menu_add, context.getString(R.string.notif_action_accept), acceptPendingIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, context.getString(R.string.notif_action_reject), rejectPendingIntent)
            .setAutoCancel(true)
            .build()

        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(notificationId, notification)
    }

    fun showFileReceivedNotification(originalFileName: String) {
        val successNotification = NotificationCompat.Builder(context, channelId)
            .setContentTitle(context.getString(R.string.notif_file_received_title))
            .setContentText(context.getString(R.string.notif_file_received_desc, originalFileName))
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setAutoCancel(true)
            .build()
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(originalFileName.hashCode(), successNotification)
    }
}
