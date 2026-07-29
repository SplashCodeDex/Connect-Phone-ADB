package com.example.dex.network

import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.IBinder

class DexService : Service() {
    private val restServerEngine = DexAppContainer.restServerEngine
    private val discoveryEngine = DexAppContainer.discoveryEngine
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun onCreate() {
        super.onCreate()
        
        // Acquire Multicast lock to ensure UDP broadcasts are received
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        multicastLock = wifiManager?.createMulticastLock("DexMulticastLock")
        multicastLock?.setReferenceCounted(true)
        multicastLock?.acquire()

        restServerEngine.startServer()
        discoveryEngine.startDiscovery()
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
}
