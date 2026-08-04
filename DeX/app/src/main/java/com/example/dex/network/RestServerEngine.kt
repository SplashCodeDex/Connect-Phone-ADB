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
        CoroutineScope(Dispatchers.IO).launch {
            val keyStorePassword = "localsend".toCharArray()
            val keyStore = SecurityProvider.generateKeyStore(keyStorePassword)

            server = embeddedServer(Netty, configure = {
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
                    json()
                }
                routing {
                    deviceRoutes(deviceConfig)
                    fileTransferRoutes(context, deviceConfig, notificationHelper)
                }
            }.start(wait = true)
        }
    }

    fun stopServer() {
        server?.stop(1000, 2000)
    }
}
