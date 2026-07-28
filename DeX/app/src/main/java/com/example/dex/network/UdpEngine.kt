package com.example.dex.network

import android.util.Log
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.MulticastSocket
import kotlin.concurrent.thread

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

data class DexPeer(val name: String, val ip: String, val lastSeen: Long)

object UdpEngine {
    private const val PORT = 53317
    private const val MULTICAST_IP = "224.0.0.167"
    private var isListening = false
    private var listenThread: Thread? = null

    private val _discoveredPeers = MutableStateFlow<List<DexPeer>>(emptyList())
    val discoveredPeers: StateFlow<List<DexPeer>> = _discoveredPeers.asStateFlow()

    fun startListening(deviceName: String, onDeviceFound: (String, String) -> Unit) {
        if (isListening) return
        isListening = true
        
        listenThread = thread {
            try {
                val group = InetAddress.getByName(MULTICAST_IP)
                val socket = MulticastSocket(PORT)
                socket.joinGroup(group)
                
                val buffer = ByteArray(1024)
                while (isListening) {
                    val packet = DatagramPacket(buffer, buffer.size)
                    socket.receive(packet)
                    val message = String(packet.data, 0, packet.length)
                    
                    if (message.contains("\"type\":\"pc\"") || message.contains("\"type\":\"phone\"")) {
                        val ip = packet.address.hostAddress ?: ""
                        val idMatch = "\"id\"\\s*:\\s*\"([^\"]+)\"".toRegex().find(message)
                        val id = idMatch?.groupValues?.get(1) ?: "Unknown"
                        
                        // Update the Flow for Compose UI
                        _discoveredPeers.update { current ->
                            val peers = current.toMutableList()
                            val existingIndex = peers.indexOfFirst { it.ip == ip }
                            if (existingIndex != -1) {
                                peers[existingIndex] = peers[existingIndex].copy(lastSeen = System.currentTimeMillis())
                            } else {
                                peers.add(DexPeer(id, ip, System.currentTimeMillis()))
                            }
                            // Clean up old peers (older than 15s)
                            peers.filter { System.currentTimeMillis() - it.lastSeen < 15000 }
                        }
                        
                        onDeviceFound(id, ip)
                    }
                }
            } catch (e: Exception) {
                Log.e("DeX", "UDP Listener Error", e)
            }
        }
    }

    fun broadcastBeacon(deviceName: String) {
        thread {
            try {
                val socket = DatagramSocket()
                val group = InetAddress.getByName(MULTICAST_IP)
                val payload = """{"id":"$deviceName","type":"phone"}""".toByteArray()
                val packet = DatagramPacket(payload, payload.size, group, PORT)
                socket.send(packet)
                socket.close()
            } catch (e: Exception) {
                Log.e("DeX", "UDP Broadcast Error", e)
            }
        }
    }
    
    fun stopListening() {
        isListening = false
        listenThread?.interrupt()
    }
}
