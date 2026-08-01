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
import io.ktor.util.cio.writeChannel
import io.ktor.utils.io.copyAndClose
import io.ktor.server.engine.EmbeddedServer
import io.ktor.server.netty.Netty
import io.ktor.server.netty.NettyApplicationEngine

object AuthState {
    val guestTokens = mutableSetOf<String>()
    var currentPairingPin: String? = null
}

class RestServerEngine {
    private var server: EmbeddedServer<*, *>? = null

    private fun verifyToken(call: io.ktor.server.application.ApplicationCall): Boolean {
        val authHeader = call.request.header(io.ktor.http.HttpHeaders.Authorization)
        if (authHeader != null && authHeader.startsWith("Bearer ")) {
            val token = authHeader.removePrefix("Bearer ")
            if (token == "dex_static_placeholder_hash_123" || AuthState.guestTokens.contains(token)) {
                return true
            }
        }
        return false
    }

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
                        
                        val deferred = kotlinx.coroutines.CompletableDeferred<Boolean>()
                        TransferPromptState.pendingPrompts[sessionId] = deferred
                        
                        val notificationId = sessionId.hashCode()
                        
                        val ctx = DexAppContainer.context!!
                        
                        val acceptIntent = android.content.Intent(ctx, FileTransferReceiver::class.java).apply {
                            action = "com.example.dex.ACCEPT_TRANSFER"
                            putExtra("SESSION_ID", sessionId)
                            putExtra("NOTIFICATION_ID", notificationId)
                        }
                        
                        val rejectIntent = android.content.Intent(ctx, FileTransferReceiver::class.java).apply {
                            action = "com.example.dex.REJECT_TRANSFER"
                            putExtra("SESSION_ID", sessionId)
                            putExtra("NOTIFICATION_ID", notificationId)
                        }
                        
                        val acceptPendingIntent = android.app.PendingIntent.getBroadcast(
                            ctx, notificationId, acceptIntent, android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
                        )
                        val rejectPendingIntent = android.app.PendingIntent.getBroadcast(
                            ctx, notificationId + 1, rejectIntent, android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
                        )
                        
                        val notification = androidx.core.app.NotificationCompat.Builder(ctx, "dex_service_channel")
                            .setContentTitle("Incoming File Transfer")
                            .setContentText("PC wants to send ${request.files.size} files.")
                            .setSmallIcon(android.R.drawable.ic_menu_share)
                            .setPriority(androidx.core.app.NotificationCompat.PRIORITY_HIGH)
                            .setDefaults(androidx.core.app.NotificationCompat.DEFAULT_ALL)
                            .addAction(android.R.drawable.ic_menu_add, "Accept", acceptPendingIntent)
                            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Reject", rejectPendingIntent)
                            .setAutoCancel(true)
                            .build()
                            
                        val nm = ctx.getSystemService(android.content.Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
                        nm.notify(notificationId, notification)
                        
                        // Wait for user action
                        val accepted = deferred.await()
                        
                        if (!accepted) {
                            call.respond(io.ktor.http.HttpStatusCode.Forbidden)
                            return@post
                        }
                        
                        val downloadsFolder = java.io.File(
                            android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_DOWNLOADS),
                            "DeX"
                        )
                        val responseFiles = mutableMapOf<String, String>()
                        for ((fileId, fileMeta) in request.files) {
                            val existing = java.io.File(downloadsFolder, fileMeta.fileName)
                            if (existing.exists() && existing.length() == fileMeta.size) continue
                            responseFiles[fileId] = UUID.randomUUID().toString()
                        }
                        
                        // ponytail: store session to map fileId to original name
                        TransferPromptState.activeSessions[sessionId] = request
                        
                        call.respond(PrepareUploadResponseDto(sessionId, responseFiles))
                    }
                    post("/api/localsend/v2/upload") {
                        val sessionId = call.request.queryParameters["sessionId"]
                        val fileId = call.request.queryParameters["fileId"]
                        
                        val session = TransferPromptState.activeSessions[sessionId]
                        if (session == null || fileId == null) {
                            call.respond(io.ktor.http.HttpStatusCode.BadRequest)
                            return@post
                        }
                        
                        val originalFileName = session.files[fileId]?.fileName ?: "unknown_file_$fileId"
                        
                        val downloadsFolder = java.io.File(
                            android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_DOWNLOADS),
                            "DeX"
                        )
                        if (!downloadsFolder.exists()) downloadsFolder.mkdirs()
                        
                        val ext = if (originalFileName.contains(".")) ".${originalFileName.substringAfterLast(".")}" else ""
                        val base = if (originalFileName.contains(".")) originalFileName.substringBeforeLast(".") else originalFileName
                        var file = java.io.File(downloadsFolder, originalFileName)
                        var counter = 1
                        while (file.exists()) {
                            file = java.io.File(downloadsFolder, "$base ($counter)$ext")
                            counter++
                        }
                        
                        val channel = call.receiveChannel()
                        channel.copyAndClose(file.writeChannel())
                        
                        // Notification for successful transfer
                        val ctx = DexAppContainer.context!!
                        val successNotification = androidx.core.app.NotificationCompat.Builder(ctx, "dex_service_channel")
                            .setContentTitle("File Received")
                            .setContentText("Saved to Downloads/DeX/$originalFileName")
                            .setSmallIcon(android.R.drawable.stat_sys_download_done)
                            .setAutoCancel(true)
                            .build()
                        val nm = ctx.getSystemService(android.content.Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
                        nm.notify(originalFileName.hashCode(), successNotification)
                        
                        call.respond(io.ktor.http.HttpStatusCode.OK)
                    }
                    post("/notify-download") {
                        val request = call.receive<Map<String, String>>()
                        val ip = request["ip"]
                        val portStr = request["port"]
                        val fileId = request["fileId"]
                        val fileName = request["fileName"] ?: "downloaded_file"
                        val fileSize = request["fileSize"]?.toLongOrNull() ?: 100L // prevent divide by zero
                        
                        if (ip != null && portStr != null && fileId != null) {
                            println("Received TCP download signal: $ip:$portStr for file $fileId")
                            val dest = java.io.File(System.getProperty("java.io.tmpdir"), fileName)
                            TcpDownloadService.download(ip, portStr.toInt(), fileId, fileName, fileSize, dest)
                            call.respond(io.ktor.http.HttpStatusCode.OK)
                        } else {
                            call.respond(io.ktor.http.HttpStatusCode.BadRequest)
                        }
                    }
                    post("/api/dex/pair/request") {
                        val pin = (100000..999999).random().toString()
                        AuthState.currentPairingPin = pin
                        val ctx = DexAppContainer.context!!
                        val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())
                        mainHandler.post {
                            android.widget.Toast.makeText(ctx, "DeX Pairing PIN: $pin", android.widget.Toast.LENGTH_LONG).show()
                        }
                        call.respond(io.ktor.http.HttpStatusCode.OK, "PIN generated")
                    }
                    post("/api/dex/pair/verify") {
                        val request = call.receive<Map<String, String>>()
                        val pin = request["pin"]
                        if (pin != null && pin == AuthState.currentPairingPin) {
                            val token = UUID.randomUUID().toString()
                            AuthState.guestTokens.add(token)
                            AuthState.currentPairingPin = null
                            call.respond(mapOf("token" to token))
                        } else {
                            call.respond(io.ktor.http.HttpStatusCode.Forbidden, "Invalid PIN")
                        }
                    }
                    get("/api/dex/browse") {
                        if (!verifyToken(call)) {
                            call.respond(io.ktor.http.HttpStatusCode.Unauthorized, "Unauthorized")
                            return@get
                        }

                        val path = call.request.queryParameters["path"] ?: "/sdcard/"
                        val dir = java.io.File(path)
                        
                        if (!dir.exists() || !dir.isDirectory) {
                            call.respond(io.ktor.http.HttpStatusCode.NotFound, "Directory not found")
                            return@get
                        }
                        
                        val files = dir.listFiles()?.map { file ->
                            BrowseFileDto(
                                name = file.name,
                                isDirectory = file.isDirectory,
                                size = file.length(),
                                path = file.absolutePath
                            )
                        }?.sortedWith(compareBy({ !it.isDirectory }, { it.name.lowercase() })) ?: emptyList()
                        
                        call.respond(files)
                    }
                    get("/api/dex/pull") {
                        if (!verifyToken(call)) {
                            call.respond(io.ktor.http.HttpStatusCode.Unauthorized, "Unauthorized")
                            return@get
                        }
                        val path = call.request.queryParameters["path"]
                        if (path == null) {
                            call.respond(io.ktor.http.HttpStatusCode.BadRequest, "Missing path parameter")
                            return@get
                        }
                        val file = java.io.File(path)
                        if (!file.exists() || !file.isFile) {
                            call.respond(io.ktor.http.HttpStatusCode.NotFound, "File not found")
                            return@get
                        }
                        
                        call.response.header(
                            io.ktor.http.HttpHeaders.ContentDisposition,
                            io.ktor.http.ContentDisposition.Attachment.withParameter(io.ktor.http.ContentDisposition.Parameters.FileName, file.name).toString()
                        )
                        call.respondFile(file)
                    }
                }
            }.start(wait = true)
        }
    }

    fun stopServer() {
        server?.stop(1000, 2000)
    }
}
