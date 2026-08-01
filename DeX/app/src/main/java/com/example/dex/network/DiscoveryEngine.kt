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
import org.json.JSONObject
import java.net.DatagramPacket
import java.net.InetSocketAddress
import java.net.MulticastSocket
import java.net.InetAddress
import android.net.wifi.WifiManager
import kotlinx.coroutines.isActive

data class DiscoveredDevice(
    val ip: String,
    val info: RegisterDto,
    val lastSeenTimestamp: Long,
    val trustLevel: String
)

class DiscoveryEngine {
    private val scope = CoroutineScope(Dispatchers.IO)
    private var cleanupJob: Job? = null
    private var udpJob: Job? = null
    private var udpSocket: MulticastSocket? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    
    private val _devices = MutableStateFlow<Map<String, DiscoveredDevice>>(emptyMap())
    val devices: StateFlow<Map<String, DiscoveredDevice>> = _devices.asStateFlow()
    
    private var nsdManager: NsdManager? = null
    private var registrationListener: NsdManager.RegistrationListener? = null
    private var discoveryListener: NsdManager.DiscoveryListener? = null
    private var appContext: Context? = null

    private val localSendInfo: RegisterDto
        get() = RegisterDto(
            alias = "DeX",
            version = "2.0",
            deviceModel = android.os.Build.MODEL ?: "Android",
            deviceType = "mobile",
            fingerprint = DexAppContainer.fingerprint,
            port = 53317,
            protocol = "https",
            download = true,
            identityHash = DexAppContainer.identityHash
        )

    fun startDiscovery(context: Context) {
        appContext = context.applicationContext
        nsdManager = context.getSystemService(Context.NSD_SERVICE) as NsdManager

        // 1. Register Service
        val serviceInfo = NsdServiceInfo().apply {
            serviceName = "DeX_Android"
            serviceType = "_dex._udp"
            port = localSendInfo.port
            setAttribute("alias", localSendInfo.alias)
            setAttribute("fingerprint", localSendInfo.fingerprint)
            setAttribute("identityHash", localSendInfo.identityHash)
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
                    if (android.os.Build.VERSION.SDK_INT >= 34) {
                        val executor = java.util.concurrent.Executors.newSingleThreadExecutor()
                        nsdManager?.registerServiceInfoCallback(service, executor, object : NsdManager.ServiceInfoCallback {
                            override fun onServiceInfoCallbackRegistrationFailed(errorCode: Int) {}
                            override fun onServiceUpdated(serviceInfo: NsdServiceInfo) {
                                handleResolvedService(serviceInfo)
                            }
                            override fun onServiceLost() {}
                            override fun onServiceInfoCallbackUnregistered() {}
                        })
                    } else {
                        @Suppress("DEPRECATION")
                        nsdManager?.resolveService(service, object : NsdManager.ResolveListener {
                            override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {}
                            override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                                handleResolvedService(serviceInfo)
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

        try {
            nsdManager?.discoverServices("_dex._udp", NsdManager.PROTOCOL_DNS_SD, discoveryListener)
        } catch (e: Exception) { e.printStackTrace() }

        // Cleanup stale devices
        cleanupJob = scope.launch {
            while (isActive) {
                delay(10000)
                val now = System.currentTimeMillis()
                _devices.update { map ->
                    val toKeep = map.filterValues { now - it.lastSeenTimestamp < 20000 }
                    val toRemove = map.keys - toKeep.keys
                    if (toRemove.isNotEmpty()) {
                        appContext?.let { ctx ->
                            try {
                                androidx.core.content.pm.ShortcutManagerCompat.removeDynamicShortcuts(ctx, toRemove.toList())
                            } catch (e: Exception) { e.printStackTrace() }
                        }
                    }
                    toKeep
                }
            }
        }
        
        // Omni-Mesh Hotspot Piercer UDP Listener
        udpJob = scope.launch {
            try {
                val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                multicastLock = wifiManager.createMulticastLock("dex_multicast_lock")
                multicastLock?.setReferenceCounted(true)
                multicastLock?.acquire()

                udpSocket = MulticastSocket(53317).apply {
                    reuseAddress = true
                    joinGroup(InetAddress.getByName("224.0.0.167"))
                }
                val buffer = ByteArray(1024)
                while (isActive) {
                    val packet = DatagramPacket(buffer, buffer.size)
                    udpSocket?.receive(packet)
                    val msg = String(packet.data, 0, packet.length)
                    
                    try {
                        val json = JSONObject(msg)
                        val fp = json.optString("fingerprint", "")
                        val alias = json.optString("alias", "Unknown")
                        val port = json.optInt("port", 53317)
                        val protocol = json.optString("protocol", "https")
                        val type = json.optString("type", "")

                        if (fp.isNotEmpty() && fp != localSendInfo.fingerprint) {
                            val ip = packet.address.hostAddress ?: ""
                            val incomingHash = if (json.has("identityHash")) json.getString("identityHash") else null
                            val dto = RegisterDto(
                                alias = alias,
                                version = json.optString("version", "2.0"),
                                deviceModel = json.optString("deviceModel", "Unknown"),
                                deviceType = json.optString("deviceType", "unknown"),
                                fingerprint = fp,
                                port = port,
                                protocol = protocol,
                                download = json.optBoolean("download", true),
                                identityHash = incomingHash
                            )
                            val level = if (incomingHash != null && incomingHash == localSendInfo.identityHash) "Auto-Trusted" else "Guest"
                            val newDevice = DiscoveredDevice(ip, dto, System.currentTimeMillis(), level)
                            _devices.update { map ->
                                val newMap = map.toMutableMap()
                                newMap[fp] = newDevice
                                newMap
                            }
                            publishShortcut(newDevice)
                        }

                        if (type == "pc" || json.optString("deviceType") == "desktop") {
                            val deviceName = android.os.Build.MODEL ?: "Android Device"
                            val replyJson = JSONObject().apply {
                                put("alias", localSendInfo.alias)
                                put("version", localSendInfo.version)
                                put("deviceModel", localSendInfo.deviceModel)
                                put("deviceType", localSendInfo.deviceType)
                                put("fingerprint", localSendInfo.fingerprint)
                                put("port", localSendInfo.port)
                                put("protocol", localSendInfo.protocol)
                                put("download", localSendInfo.download)
                                put("identityHash", localSendInfo.identityHash)
                            }
                            val replyMsg = replyJson.toString()
                            val replyData = replyMsg.toByteArray(Charsets.UTF_8)
                            val replyPacket = DatagramPacket(replyData, replyData.size, InetAddress.getByName("224.0.0.167"), 53317)
                            udpSocket?.send(replyPacket)
                        }
                    } catch (e: Exception) {}
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    private fun handleResolvedService(serviceInfo: NsdServiceInfo) {
        val fpBytes = serviceInfo.attributes["fingerprint"]
        val aliasBytes = serviceInfo.attributes["alias"]
        val hashBytes = serviceInfo.attributes["identityHash"]
        val fp = fpBytes?.let { String(it) }
        val alias = aliasBytes?.let { String(it) } ?: "Unknown"
        val incomingHash = hashBytes?.let { String(it) }

        if (fp != null && fp != localSendInfo.fingerprint) {
            val ip = if (android.os.Build.VERSION.SDK_INT >= 34) {
                serviceInfo.hostAddresses.firstOrNull()?.hostAddress ?: ""
            } else {
                @Suppress("DEPRECATION")
                serviceInfo.host?.hostAddress ?: ""
            }

            val dto = RegisterDto(
                alias = alias,
                version = "2.0",
                deviceModel = "Unknown",
                deviceType = "unknown",
                fingerprint = fp,
                port = serviceInfo.port,
                protocol = "https",
                download = true,
                identityHash = incomingHash
            )
            val level = if (incomingHash != null && incomingHash == localSendInfo.identityHash) "Auto-Trusted" else "Guest"
            val newDevice = DiscoveredDevice(
                ip = ip,
                info = dto,
                lastSeenTimestamp = System.currentTimeMillis(),
                trustLevel = level
            )
            _devices.update { map ->
                val newMap = map.toMutableMap()
                newMap[fp] = newDevice
                newMap
            }
            publishShortcut(newDevice)
        }
    }

    private fun publishShortcut(device: DiscoveredDevice) {
        if (device.info.deviceType != "desktop" && device.info.deviceType != "pc") return
        val ctx = appContext ?: return
        try {
            val intent = android.content.Intent(ctx, com.example.dex.ShareTargetActivity::class.java).apply {
                action = android.content.Intent.ACTION_SEND
                putExtra("EXTRA_TARGET_FINGERPRINT", device.info.fingerprint)
            }

            val shortcut = androidx.core.content.pm.ShortcutInfoCompat.Builder(ctx, device.info.fingerprint)
                .setShortLabel(device.info.alias)
                .setLongLabel("Send to ${device.info.alias}")
                .setIcon(androidx.core.graphics.drawable.IconCompat.createWithResource(ctx, com.example.dex.R.mipmap.ic_launcher))
                .setIntent(intent)
                .setCategories(setOf("com.example.dex.category.DIRECT_SHARE_TARGET"))
                .setLongLived(true)
                .build()

            androidx.core.content.pm.ShortcutManagerCompat.addDynamicShortcuts(ctx, listOf(shortcut))
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun stopDiscovery() {
        try {
            if (registrationListener != null) {
                nsdManager?.unregisterService(registrationListener)
                registrationListener = null
            }
        } catch (e: Exception) { e.printStackTrace() }

        try {
            if (discoveryListener != null) {
                nsdManager?.stopServiceDiscovery(discoveryListener)
                discoveryListener = null
            }
        } catch (e: Exception) { e.printStackTrace() }

        cleanupJob?.cancel()
        udpJob?.cancel()
        try {
            multicastLock?.release()
        } catch (e: Exception) { e.printStackTrace() }
        udpSocket?.close()
    }
}
