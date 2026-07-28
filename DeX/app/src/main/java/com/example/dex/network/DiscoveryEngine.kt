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

class DiscoveryEngine {
    private val scope = CoroutineScope(Dispatchers.IO)
    private var listenJob: Job? = null
    private var broadcastJob: Job? = null
    private var socket: DatagramSocket? = null

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
        try {
            socket = DatagramSocket(null).apply {
                reuseAddress = true
                bind(InetSocketAddress(53317))
                broadcast = true
            }
        } catch (e: Exception) {
            e.printStackTrace()
            return
        }

        listenJob = scope.launch {
            val buffer = ByteArray(1024)
            val packet = DatagramPacket(buffer, buffer.size)
            while (true) {
                try {
                    socket?.receive(packet)
                    val data = String(packet.data, 0, packet.length)
                    println("Received discovery packet from ${packet.address}: $data")
                    // In a real app, we parse this and update the UI with discovered devices
                } catch (e: Exception) {
                    break
                }
            }
        }

        broadcastJob = scope.launch {
            while (true) {
                try {
                    val payload = Json.encodeToString(localSendInfo)
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
