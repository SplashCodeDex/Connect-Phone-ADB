package com.example.dex.network

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.app.NotificationManager
import kotlinx.coroutines.CompletableDeferred
import java.util.concurrent.ConcurrentHashMap

object TransferPromptState {
    val pendingPrompts = ConcurrentHashMap<String, CompletableDeferred<Boolean>>()
    val activeSessions = ConcurrentHashMap<String, PrepareUploadRequestDto>()
}

class FileTransferReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val sessionId = intent.getStringExtra("SESSION_ID") ?: return
        val action = intent.action
        
        val deferred = TransferPromptState.pendingPrompts.remove(sessionId)
        if (deferred != null) {
            deferred.complete(action == "com.example.dex.ACCEPT_TRANSFER")
        }
        
        // Cancel notification
        val notificationId = intent.getIntExtra("NOTIFICATION_ID", 0)
        if (notificationId != 0) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.cancel(notificationId)
        }
    }
}
