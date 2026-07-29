package com.example.dex.network

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

data class DiscoveredDevice(
    val ip: String,
    val info: RegisterDto,
    val lastSeenTimestamp: Long
)

class DiscoveryEngine {
    private val scope = CoroutineScope(Dispatchers.IO)
    private var cleanupJob: Job? = null
    
    private val _devices = MutableStateFlow<Map<String, DiscoveredDevice>>(emptyMap())
    val devices: StateFlow<Map<String, DiscoveredDevice>> = _devices.asStateFlow()
    
    private var nsdManager: NsdManager? = null
    private var registrationListener: NsdManager.RegistrationListener? = null
    private var discoveryListener: NsdManager.DiscoveryListener? = null

    private val localSendInfo = RegisterDto(
        alias = "DeX",
        version = "2.0",
        deviceModel = "Android",
        deviceType = "mobile",
        fingerprint = "dex-fingerprint",
        port = 53317,
        protocol = "https",
        download = true
    )

    fun startDiscovery(context: Context) {
        nsdManager = context.getSystemService(Context.NSD_SERVICE) as NsdManager

        // 1. Register Service
        val serviceInfo = NsdServiceInfo().apply {
            serviceName = "DeX_Android"
            serviceType = "_dex._udp"
            port = localSendInfo.port
            setAttribute("alias", localSendInfo.alias)
            setAttribute("fingerprint", localSendInfo.fingerprint)
        }

        registrationListener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(NsdServiceInfo: NsdServiceInfo) {}
            override fun onRegistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {}
            override fun onServiceUnregistered(arg0: NsdServiceInfo) {}
            override fun onUnregistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {}
        }

        try {
            nsdManager?.registerService(serviceInfo, NsdManager.PROTOCOL_DNS_SD, registrationListener)
        } catch (e: Exception) { e.printStackTrace() }

        // 2. Discover Services
        discoveryListener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(regType: String) {}
            override fun onServiceFound(service: NsdServiceInfo) {
                if (service.serviceType.contains("_dex._udp")) {
                    nsdManager?.resolveService(service, object : NsdManager.ResolveListener {
                        override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {}
                        override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                            val fpBytes = serviceInfo.attributes["fingerprint"]
                            val aliasBytes = serviceInfo.attributes["alias"]
                            val fp = fpBytes?.let { String(it) }
                            val alias = aliasBytes?.let { String(it) } ?: "Unknown"

                            if (fp != null && fp != localSendInfo.fingerprint) {
                                val dto = RegisterDto(
                                    alias = alias,
                                    version = "2.0",
                                    deviceModel = "Unknown",
                                    deviceType = "unknown",
                                    fingerprint = fp,
                                    port = serviceInfo.port,
                                    protocol = "https",
                                    download = true
                                )
                                _devices.update { map ->
                                    val newMap = map.toMutableMap()
                                    newMap[fp] = DiscoveredDevice(
                                        ip = serviceInfo.host.hostAddress ?: "",
                                        info = dto,
                                        lastSeenTimestamp = System.currentTimeMillis()
                                    )
                                    newMap
                                }
                            }
                        }
                    })
                }
            }
            override fun onServiceLost(service: NsdServiceInfo) {}
            override fun onDiscoveryStopped(serviceType: String) {}
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {}
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
        }

        try {
            nsdManager?.discoverServices("_dex._udp", NsdManager.PROTOCOL_DNS_SD, discoveryListener)
        } catch (e: Exception) { e.printStackTrace() }

        // Cleanup stale devices
        cleanupJob = scope.launch {
            while (true) {
                delay(10000)
                val now = System.currentTimeMillis()
                _devices.update { map ->
                    map.filterValues { now - it.lastSeenTimestamp < 20000 }
                }
            }
        }
    }

    fun stopDiscovery() {
        try {
            registrationListener?.let { nsdManager?.unregisterService(it) }
            discoveryListener?.let { nsdManager?.stopServiceDiscovery(it) }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        cleanupJob?.cancel()
    }
}
