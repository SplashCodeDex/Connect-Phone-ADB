package com.example.dex.network

import android.content.Context
import android.net.wifi.WifiManager
import timber.log.Timber
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.MulticastSocket
import java.net.NetworkInterface

class UdpMulticastManager(
    private val context: Context,
    private val localInfo: RegisterDto
) {
    private val scope = CoroutineScope(Dispatchers.IO)
    private var udpJob: Job? = null
    private var udpSocket: MulticastSocket? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    fun start() {
        udpJob = scope.launch {
            runCatching {
                val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                multicastLock = wifiManager.createMulticastLock("dex_multicast_lock").apply {
                    setReferenceCounted(true)
                    acquire()
                }

                udpSocket = MulticastSocket(53317).apply {
                    reuseAddress = true
                    val groupAddr = InetSocketAddress(InetAddress.getByName("224.0.0.167"), 53317)
                    NetworkInterface.getNetworkInterfaces().toList().forEach { ni ->
                        runCatching {
                            if (ni.isUp && !ni.isLoopback && ni.supportsMulticast()) {
                                joinGroup(groupAddr, ni)
                            }
                        }
                    }
                }

                val buffer = ByteArray(2048)
                while (isActive) {
                    val packet = DatagramPacket(buffer, buffer.size)
                    udpSocket?.receive(packet)
                    handleIncomingPacket(packet)
                }
            }.onFailure { Timber.e(it, "Multicast loop failed") }
        }
    }

    private fun handleIncomingPacket(packet: DatagramPacket) {
        val msg = String(packet.data, 0, packet.length)
        runCatching {
            val json = JSONObject(msg)
            val fp = json.optString("fingerprint", "")
            if (fp.isNotEmpty() && fp != localInfo.fingerprint) {
                sendReply(packet)
            }
        }
    }

    private fun sendReply(packet: DatagramPacket) {
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
            val replyData = replyJson.toString().toByteArray(Charsets.UTF_8)
            val mcastPacket = DatagramPacket(replyData, replyData.size, InetAddress.getByName("224.0.0.167"), 53317)
            val ucastPacket = DatagramPacket(replyData, replyData.size, packet.address, packet.port)
            
            NetworkInterface.getNetworkInterfaces().toList().forEach { ni ->
                runCatching {
                    if (ni.isUp && !ni.isLoopback && ni.supportsMulticast()) {
                        udpSocket?.networkInterface = ni
                        udpSocket?.send(mcastPacket)
                    }
                }
            }
            runCatching { DatagramSocket().use { it.send(ucastPacket) } }
        }
    }

    fun stop() {
        udpJob?.cancel()
        runCatching { multicastLock?.release() }
        runCatching { udpSocket?.close() }
    }
}
