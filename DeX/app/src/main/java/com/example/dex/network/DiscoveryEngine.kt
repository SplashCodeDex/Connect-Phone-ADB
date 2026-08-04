package com.example.dex.network

import android.content.Context
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress

class DiscoveryEngine(
    private val deviceConfig: DeviceConfig,
    private val context: Context
) {
    private val scope = CoroutineScope(Dispatchers.IO)
    private var cleanupJob: Job? = null
    
    private val _devices = MutableStateFlow<Map<String, DiscoveredDevice>>(emptyMap())
    val devices: StateFlow<Map<String, DiscoveredDevice>> = _devices.asStateFlow()
    
    private var nsdManagerHelper: NsdManagerHelper? = null
    private var udpManager: UdpMulticastManager? = null

    private val localInfo: RegisterDto
        get() = RegisterDto(
            alias = "DeX",
            version = "2.0",
            deviceModel = android.os.Build.MODEL ?: "Android",
            deviceType = "mobile",
            fingerprint = deviceConfig.fingerprint,
            port = 53317,
            protocol = "https",
            download = true,
            identityHash = deviceConfig.identityHash
        )

    fun startDiscovery() {
        val onDeviceFound: (DiscoveredDevice) -> Unit = { newDevice ->
            _devices.update { map ->
                map.toMutableMap().apply { put(newDevice.info.fingerprint, newDevice) }
            }
        }

        nsdManagerHelper = NsdManagerHelper(context, localInfo, onDeviceFound).apply { start() }
        udpManager = UdpMulticastManager(context, localInfo, onDeviceFound).apply { start() }

        cleanupJob = scope.launch {
            while (isActive) {
                delay(10000)
                val now = System.currentTimeMillis()
                _devices.update { map ->
                    map.filterValues { now - it.lastSeenTimestamp < 20000 }
                }
            }
        }
    }

    fun stopDiscovery() {
        nsdManagerHelper?.stop()
        udpManager?.stop()
        cleanupJob?.cancel()
    }

    fun sendManualDiscovery(ip: String) {
        scope.launch {
            runCatching {
                val replyJson = JSONObject().apply {
                    put("alias", localInfo.alias)
                    put("version", localInfo.version)
                    put("deviceModel", localInfo.deviceModel)
                    put("deviceType", localInfo.deviceType)
                    put("fingerprint", localInfo.fingerprint)
                    put("port", localInfo.port)
                    put("protocol", localInfo.protocol)
                    put("download", localInfo.download)
                    put("identityHash", localInfo.identityHash)
                }
                val data = replyJson.toString().toByteArray(Charsets.UTF_8)
                DatagramSocket().use { ds ->
                    ds.send(DatagramPacket(data, data.size, InetAddress.getByName(ip), 53317))
                }
            }
        }
    }
}
