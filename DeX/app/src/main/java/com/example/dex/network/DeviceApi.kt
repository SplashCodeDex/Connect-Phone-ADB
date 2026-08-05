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
                download = true,
                identityHash = deviceConfig.identityHash
            )
        )
    }
    
    post("/api/localsend/v2/register") {
        val request = call.receive<RegisterDto>()
        println("Registered device: ${request.alias}")
        call.respond(mapOf("sessionId" to UUID.randomUUID().toString()))
    }
    
    post("/api/localsend/v2/pair-prompt") {
        val request = call.receive<Map<String, String>>()
        val alias = request["alias"] ?: "Unknown Device"
        val fingerprint = request["fingerprint"]
        val pin = request["pin"]
        val token = request["token"]

        if (fingerprint != null && pin != null) {
            if (AuthState.incomingPairRequest.value != null) {
                call.respond(HttpStatusCode.TooManyRequests, "A pairing request is already pending")
                return@post
            }
            val deferred = kotlinx.coroutines.CompletableDeferred<Boolean>()
            AuthState.incomingPairRequest.value = PairRequestInfo(alias, fingerprint, pin, deferred)
            
            val accepted = kotlinx.coroutines.withTimeoutOrNull(60_000) { deferred.await() }
            AuthState.incomingPairRequest.value = null
            if (accepted == true) {
                DeviceManager.savePairedFingerprint(fingerprint)
                if (!token.isNullOrEmpty()) DeviceManager.savePairedToken(fingerprint, token)
                call.respond(HttpStatusCode.OK)
            } else {
                call.respond(HttpStatusCode.Forbidden, "Pairing rejected or timed out")
            }
        } else {
            call.respond(HttpStatusCode.BadRequest, "Missing fingerprint or pin")
        }
    }
}
