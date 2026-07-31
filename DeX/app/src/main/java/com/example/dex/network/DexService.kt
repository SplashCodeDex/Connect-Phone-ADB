package com.example.dex.network

import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.IBinder

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import androidx.core.app.NotificationCompat
import android.content.pm.ServiceInfo

class DexService : Service() {
    private val restServerEngine = DexAppContainer.restServerEngine
    private val discoveryEngine = DexAppContainer.discoveryEngine
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun onCreate() {
        super.onCreate()
        DexAppContainer.context = this
        startForegroundServiceNotification()
        
        // Acquire Multicast lock to ensure UDP broadcasts are received
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        multicastLock = wifiManager?.createMulticastLock("DexMulticastLock")
        multicastLock?.setReferenceCounted(true)
        multicastLock?.acquire()

        restServerEngine.startServer()
        discoveryEngine.startDiscovery(this)
    }

    override fun onDestroy() {
        super.onDestroy()
        restServerEngine.stopServer()
        discoveryEngine.stopDiscovery()
        
        multicastLock?.let {
            if (it.isHeld) {
                it.release()
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    private fun startForegroundServiceNotification() {
        val channelId = "dex_service_channel"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "DeX Background Service",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }

        val notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle("DeX is running")
            .setContentText("Listening for PC connections...")
            .setSmallIcon(android.R.drawable.ic_menu_share)
            .build()

        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(1, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        } else {
            startForeground(1, notification)
        }
    }
}
