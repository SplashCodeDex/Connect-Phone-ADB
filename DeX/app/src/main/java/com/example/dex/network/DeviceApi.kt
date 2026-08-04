package com.example.dex.network

import io.ktor.server.application.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import io.ktor.http.HttpStatusCode
import java.util.UUID

fun Route.deviceRoutes(deviceConfig: DeviceConfig) {
    get("/api/localsend/v2/info") {
        call.respond(
            RegisterDto(
                alias = "DeX",
                version = "2.0",
                deviceModel = android.os.Build.MODEL ?: "Android",
                deviceType = "mobile",
                fingerprint = deviceConfig.fingerprint,
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
    
    post("/api/dex/pair/request") {
        val pin = (100000..999999).random().toString()
        AuthState.currentPairingPin.value = pin
        call.respond(HttpStatusCode.OK, "PIN generated")
    }
    
    post("/api/dex/pair/verify") {
        val request = call.receive<Map<String, String>>()
        val pin = request["pin"]
        if (pin != null && pin == AuthState.currentPairingPin.value) {
            val token = UUID.randomUUID().toString()
            AuthState.guestTokens.add(token)
            AuthState.currentPairingPin.value = null
            call.respond(mapOf("token" to token))
        } else {
            call.respond(HttpStatusCode.Forbidden, "Invalid PIN")
        }
    }
}
