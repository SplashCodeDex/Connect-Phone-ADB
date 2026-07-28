package com.example.dex.network

import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.IBinder
import android.util.Log

class DexService : Service() {
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun onCreate() {
        super.onCreate()
        
        // Android requires an explicit MulticastLock, otherwise the OS drops UDP broadcasts to save battery!
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        multicastLock = wifiManager.createMulticastLock("DexLock")
        multicastLock?.setReferenceCounted(true)
        multicastLock?.acquire()
        
        Log.i("DeX", "Service Started, Multicast Lock Acquired")
        
        // Start listening to the network using the device model as the ID
        UdpEngine.startListening(android.os.Build.MODEL) { name, ip ->
            Log.i("DeX", "Discovered: $name at $ip")
            // TODO: Expose this list to Jetpack Compose UI via StateFlow
        }
        
        // Start broadcasting our existence every 5 seconds
        Thread {
            while (multicastLock?.isHeld == true) {
                UdpEngine.broadcastBeacon(android.os.Build.MODEL)
                Thread.sleep(5000)
            }
        }.start()
    }

    override fun onDestroy() {
        super.onDestroy()
        UdpEngine.stopListening()
        if (multicastLock?.isHeld == true) {
            multicastLock?.release()
        }
        Log.i("DeX", "Service Stopped, Multicast Lock Released")
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
