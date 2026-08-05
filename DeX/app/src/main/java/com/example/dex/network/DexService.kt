package com.example.dex.network

import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.IBinder
import android.content.pm.ServiceInfo
import androidx.core.app.ServiceCompat
import org.koin.android.ext.android.inject

class DexService : Service() {
    private val restServerEngine: RestServerEngine by inject()
    private val discoveryEngine: DiscoveryEngine by inject()
    private val notificationHelper: NotificationHelper by inject()
    
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun onCreate() {
        super.onCreate()
        
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceCompat.startForeground(
                this, 1, notificationHelper.getForegroundServiceNotification(),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE or ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            startForeground(1, notificationHelper.getForegroundServiceNotification())
        }
        
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

    override fun onTimeout(startId: Int, fgsType: Int) {
        // Android 15+ dataSync FGS 6-hour limit: stop gracefully to avoid ForegroundServiceDidNotStopInTimeException
        if (fgsType and ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC != 0) {
            stopSelf(startId)
        }
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }
}
