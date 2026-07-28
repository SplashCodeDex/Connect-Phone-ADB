package com.example.dex.network

import io.ktor.serialization.kotlinx.json.*
import io.ktor.server.application.*
import io.ktor.server.cio.*
import io.ktor.server.engine.*
import io.ktor.server.plugins.contentnegotiation.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable

class RestServerEngine {
    private var server: ApplicationEngine? = null

    fun startServer() {
        val keyStorePassword = "localsend".toCharArray()
        val keyStore = SecurityProvider.generateKeyStore(keyStorePassword)

        val environment = applicationEngineEnvironment {
            sslConnector(
                keyStore = keyStore,
                keyAlias = "localsend_key",
                keyStorePassword = { keyStorePassword },
                privateKeyPassword = { keyStorePassword }
            ) {
                port = 53317
            }
            module {
                install(ContentNegotiation) {
                    json()
                }
                routing {
                    get("/api/localsend/v2/info") {
                        call.respond(
                            RegisterDto(
                                alias = "DeX",
                                version = "2.0",
                                deviceModel = "Android",
                                deviceType = "mobile",
                                fingerprint = "dex-fingerprint",
                                port = 53317,
                                protocol = "https",
                                download = true
                            )
                        )
                    }
                    post("/api/localsend/v2/register") {
                        val request = call.receive<RegisterDto>()
                        println("Registered device: ${request.alias}")
                        call.respond(mapOf("sessionId" to UUID.randomUUID().toString()))
                    }
                    post("/api/localsend/v2/prepare-upload") {
                        val request = call.receive<PrepareUploadRequestDto>()
                        val sessionId = UUID.randomUUID().toString()
                        val responseFiles = request.files.mapValues { UUID.randomUUID().toString() }
                        call.respond(PrepareUploadResponseDto(sessionId, responseFiles))
                    }
                    post("/api/localsend/v2/upload") {
                        val sessionId = call.request.queryParameters["sessionId"]
                        val fileId = call.request.queryParameters["fileId"]
                        // TODO: Save call.receiveChannel() to disk
                        call.respond(io.ktor.http.HttpStatusCode.OK)
                    }
                }
            }
        }

        CoroutineScope(Dispatchers.IO).launch {
            server = embeddedServer(CIO, environment).start(wait = true)
        }
    }

    fun stopServer() {
        server?.stop(1000, 2000)
    }
}
