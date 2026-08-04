package com.example.dex.network

import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.util.Base64

class ClipboardReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == "com.example.dex.SET_CLIPBOARD") {
            val b64 = intent.getStringExtra("text_b64") ?: return
            val text = String(Base64.decode(b64, Base64.DEFAULT), Charsets.UTF_8)
            val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            val clip = ClipData.newPlainText("DeX", text)
            clipboard.setPrimaryClip(clip)
        }
    }
}
