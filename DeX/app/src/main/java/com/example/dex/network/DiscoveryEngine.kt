package com.example.dex.network

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
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
    private var listenJob: Job? = null
    private var broadcastJob: Job? = null
    private var socket: DatagramSocket? = null
    
    private val _devices = MutableStateFlow<Map<String, DiscoveredDevice>>(emptyMap())
    val devices: StateFlow<Map<String, DiscoveredDevice>> = _devices.asStateFlow()
    
    private val json = Json { ignoreUnknownKeys = true }

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

    fun startDiscovery() {
        listenJob = scope.launch {
            try {
                socket = DatagramSocket(null).apply {
                    reuseAddress = true
                    bind(InetSocketAddress(53317))
                    broadcast = true
                }
            } catch (e: Exception) {
                e.printStackTrace()
                return@launch
            }

            val buffer = ByteArray(1024)
            val packet = DatagramPacket(buffer, buffer.size)
            while (true) {
                try {
                    socket?.receive(packet)
                    val data = String(packet.data, 0, packet.length)
                    val ipStr = packet.address.hostAddress ?: continue
                    
                    try {
                        val dto = json.decodeFromString<RegisterDto>(data)
                        // Ignore self discovery
                        if (dto.fingerprint != localSendInfo.fingerprint) {
                            _devices.update { map ->
                                val newMap = map.toMutableMap()
                                newMap[dto.fingerprint] = DiscoveredDevice(
                                    ip = ipStr,
                                    info = dto,
                                    lastSeenTimestamp = System.currentTimeMillis()
                                )
                                newMap
                            }
                        }
                    } catch (e: Exception) {
                        // Not a valid localsend packet
                    }
                } catch (e: Exception) {
                    break
                }
            }
        }
        
        // Cleanup stale devices
        scope.launch {
            while (true) {
                delay(10000)
                val now = System.currentTimeMillis()
                _devices.update { map ->
                    map.filterValues { now - it.lastSeenTimestamp < 20000 }
                }
            }
        }

        broadcastJob = scope.launch {
            while (true) {
                try {
                    val payload = json.encodeToString(localSendInfo)
                    val bytes = payload.toByteArray()
                    val broadcastPacket = DatagramPacket(
                        bytes, bytes.size, InetAddress.getByName("255.255.255.255"), 53317
                    )
                    socket?.send(broadcastPacket)
                } catch (e: Exception) {
                    e.printStackTrace()
                }
                delay(2000) // Broadcast every 2 seconds
            }
        }
    }

    fun stopDiscovery() {
        listenJob?.cancel()
        broadcastJob?.cancel()
        socket?.close()
    }
}
