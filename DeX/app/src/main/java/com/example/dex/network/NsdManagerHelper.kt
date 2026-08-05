package com.example.dex.network

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo

class NsdManagerHelper(
    private val context: Context,
    private val localInfo: RegisterDto,
    private val onDeviceFound: (DiscoveredDevice) -> Unit
) {
    private val nsdManager = context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private var registrationListener: NsdManager.RegistrationListener? = null
    private var discoveryListener: NsdManager.DiscoveryListener? = null

    fun start() {
        registerService()
        discoverServices()
    }

    fun stop() {
        runCatching { registrationListener?.let { nsdManager.unregisterService(it) } }
        runCatching { discoveryListener?.let { nsdManager.stopServiceDiscovery(it) } }
        registrationListener = null
        discoveryListener = null
    }

    private fun registerService() {
        val serviceInfo = NsdServiceInfo().apply {
            serviceName = "DeX_Android"
            serviceType = "_dex._udp"
            port = localInfo.port
            setAttribute("alias", localInfo.alias)
            setAttribute("fingerprint", localInfo.fingerprint)
            setAttribute("identityHash", localInfo.identityHash)
            setAttribute("deviceModel", localInfo.deviceModel)
            setAttribute("deviceType", localInfo.deviceType)
        }
        
        registrationListener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(NsdServiceInfo: NsdServiceInfo) {}
            override fun onRegistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {}
            override fun onServiceUnregistered(arg0: NsdServiceInfo) {}
            override fun onUnregistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {}
        }
        
        runCatching { nsdManager.registerService(serviceInfo, NsdManager.PROTOCOL_DNS_SD, registrationListener) }
    }

    private fun discoverServices() {
        discoveryListener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(regType: String) {}
            override fun onServiceFound(service: NsdServiceInfo) {
                if (service.serviceType.contains("_dex._udp")) {
                    if (android.os.Build.VERSION.SDK_INT >= 34) {
                        val executor = java.util.concurrent.Executors.newSingleThreadExecutor()
                        nsdManager.registerServiceInfoCallback(service, executor, object : NsdManager.ServiceInfoCallback {
                            override fun onServiceInfoCallbackRegistrationFailed(errorCode: Int) {}
                            override fun onServiceUpdated(serviceInfo: NsdServiceInfo) {
                                handleResolved(serviceInfo)
                            }
                            override fun onServiceLost() {}
                            override fun onServiceInfoCallbackUnregistered() {}
                        })
                    } else {
                        @Suppress("DEPRECATION")
                        nsdManager.resolveService(service, object : NsdManager.ResolveListener {
                            override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {}
                            override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                                handleResolved(serviceInfo)
                            }
                        })
                    }
                }
            }
            override fun onServiceLost(service: NsdServiceInfo) {}
            override fun onDiscoveryStopped(serviceType: String) {}
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {}
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
        }
        runCatching { nsdManager.discoverServices("_dex._udp", NsdManager.PROTOCOL_DNS_SD, discoveryListener) }
    }

    private fun handleResolved(serviceInfo: NsdServiceInfo) {
        val fp = serviceInfo.attributes["fingerprint"]?.let { String(it) } ?: return
        if (fp == localInfo.fingerprint) return
        
        val ip = if (android.os.Build.VERSION.SDK_INT >= 34) {
            serviceInfo.hostAddresses.firstOrNull()?.hostAddress ?: ""
        } else {
            @Suppress("DEPRECATION")
            serviceInfo.host?.hostAddress ?: ""
        }
        
        val alias = serviceInfo.attributes["alias"]?.let { String(it) } ?: "Unknown"
        val incomingHash = serviceInfo.attributes["identityHash"]?.let { String(it) }
        val deviceModel = serviceInfo.attributes["deviceModel"]?.let { String(it) } ?: "Unknown"
        val deviceType = serviceInfo.attributes["deviceType"]?.let { String(it) } ?: "unknown"
        
        val dto = RegisterDto(
            alias = alias,
            version = "2.0",
            deviceModel = deviceModel,
            deviceType = deviceType,
            fingerprint = fp,
            port = serviceInfo.port,
            protocol = "https",
            download = true,
            identityHash = incomingHash
        )
        val level = if (incomingHash != null && incomingHash == localInfo.identityHash) "Auto-Trusted" else "Guest"
        onDeviceFound(DiscoveredDevice(ip, dto, System.currentTimeMillis(), level))
    }
}
