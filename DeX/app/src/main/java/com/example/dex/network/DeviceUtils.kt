package com.example.dex.network

import android.content.Context
import android.provider.Settings
import android.os.Build

fun getDeviceName(context: Context): String {
    return runCatching {
        Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME) 
            ?: Settings.Secure.getString(context.contentResolver, "bluetooth_name")
    }.getOrNull() ?: Build.MODEL ?: "Android Device"
}
