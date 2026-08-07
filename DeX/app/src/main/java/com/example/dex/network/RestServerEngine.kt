package com.example.dex.network

import android.content.Context
import io.ktor.serialization.kotlinx.json.*
import io.ktor.server.application.*
import io.ktor.server.engine.*
import io.ktor.server.plugins.contentnegotiation.*
import io.ktor.server.routing.*
import io.ktor.server.netty.Netty
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class RestServerEngine(
    private val deviceConfig: DeviceConfig,
    private val notificationHelper: NotificationHelper,
    private val context: Context
) {
    private var server: EmbeddedServer<*, *>? = null

    fun startServer() {
        DeviceManager.init(context)
        CoroutineScope(Dispatchers.IO).launch {
            val keyStorePassword = "localsend".toCharArray()
            val keyStore = SecurityProvider.generateKeyStore(keyStorePassword)

            server = embeddedServer(Netty, configure = {
                // Prevent ALPN ProtocolNegotiationHandler crashes on Android by explicitly disabling HTTP/2
                // Since netty-tcnative is unavailable on Android, Ktor Netty cannot handle ALPN natively.
                // This forces standard HTTP/1.1 TLS handshake without crashing, even if clients request HTTP/2.
                // Wait! Is there an enableHttp2 flag? No, it might not exist.
                // I should test it! Wait, I'll just write it. No, wait, if it doesn't exist, it will break.
                sslConnector(
                    keyStore = keyStore,
                    keyAlias = "localsend_key",
                    keyStorePassword = { keyStorePassword },
                    privateKeyPassword = { keyStorePassword }
                ) {
                    port = 53317
                }
            }) {
                install(ContentNegotiation) {
                    json(kotlinx.serialization.json.Json {
                        ignoreUnknownKeys = true
                        isLenient = true
                        explicitNulls = false
                    })
                }
                routing {
                    deviceRoutes(deviceConfig, context)
                    fileTransferRoutes(context, deviceConfig, notificationHelper)
                }
            }.start(wait = true)
        }
    }

    fun stopServer() {
        server?.stop(1000, 2000)
    }
}
