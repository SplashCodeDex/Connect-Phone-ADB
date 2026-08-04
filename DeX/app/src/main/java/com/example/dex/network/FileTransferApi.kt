package com.example.dex.network

import android.content.Context
import android.os.Environment
import io.ktor.server.application.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import io.ktor.http.HttpStatusCode
import io.ktor.http.HttpHeaders
import io.ktor.http.ContentDisposition
import io.ktor.util.cio.writeChannel
import io.ktor.utils.io.copyAndClose
import java.io.File
import java.util.UUID
import kotlinx.coroutines.CompletableDeferred

fun verifyToken(call: ApplicationCall, deviceConfig: DeviceConfig): Boolean {
    val authHeader = call.request.header(HttpHeaders.Authorization)
    if (authHeader != null && authHeader.startsWith("Bearer ")) {
        val token = authHeader.removePrefix("Bearer ")
        if (token == deviceConfig.identityHash || AuthState.guestTokens.contains(token)) {
            return true
        }
    }
    return false
}

fun Route.fileTransferRoutes(
    context: Context,
    deviceConfig: DeviceConfig,
    notificationHelper: NotificationHelper
) {
    post("/api/localsend/v2/prepare-upload") {
        val request = call.receive<PrepareUploadRequestDto>()
        val sessionId = UUID.randomUUID().toString()
        val deferred = CompletableDeferred<Boolean>()
        TransferState.pendingPrompts[sessionId] = deferred
        
        val notificationId = sessionId.hashCode()
        notificationHelper.showIncomingFileNotification(sessionId, notificationId, request.files.size)
        
        val accepted = deferred.await()
        if (!accepted) {
            call.respond(HttpStatusCode.Forbidden)
            return@post
        }
        
        val downloadsFolder = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "DeX")
        val responseFiles = mutableMapOf<String, String>()
        for ((fileId, fileMeta) in request.files) {
            val existing = File(downloadsFolder, fileMeta.fileName)
            if (existing.exists() && existing.length() == fileMeta.size) continue
            responseFiles[fileId] = UUID.randomUUID().toString()
        }
        
        TransferState.activeSessions[sessionId] = request
        call.respond(PrepareUploadResponseDto(sessionId, responseFiles))
    }

    post("/api/localsend/v2/upload") {
        val sessionId = call.request.queryParameters["sessionId"]
        val fileId = call.request.queryParameters["fileId"]
        
        val session = TransferState.activeSessions[sessionId]
        if (session == null || fileId == null) {
            call.respond(HttpStatusCode.BadRequest)
            return@post
        }
        
        val originalFileName = session.files[fileId]?.fileName ?: "unknown_file_$fileId"
        val downloadsFolder = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "DeX")
        if (!downloadsFolder.exists()) downloadsFolder.mkdirs()
        
        val ext = if (originalFileName.contains(".")) ".${originalFileName.substringAfterLast(".")}" else ""
        val base = if (originalFileName.contains(".")) originalFileName.substringBeforeLast(".") else originalFileName
        var file = File(downloadsFolder, originalFileName)
        var counter = 1
        while (file.exists()) {
            file = File(downloadsFolder, "$base ($counter)$ext")
            counter++
        }
        
        val channel = call.receiveChannel()
        channel.copyAndClose(file.writeChannel())
        
        notificationHelper.showFileReceivedNotification(originalFileName)
        call.respond(HttpStatusCode.OK)
    }

    post("/notify-download") {
        val request = call.receive<Map<String, String>>()
        val ip = request["ip"]
        val portStr = request["port"]
        val fileId = request["fileId"]
        val fileName = request["fileName"] ?: "downloaded_file"
        val fileSize = request["fileSize"]?.toLongOrNull() ?: 100L
        
        if (ip != null && portStr != null && fileId != null) {
            println("Received TCP download signal: $ip:$portStr for file $fileId")
            val dest = File(System.getProperty("java.io.tmpdir"), fileName)
            TcpDownloadService.download(context, ip, portStr.toInt(), fileId, fileName, fileSize, dest)
            call.respond(HttpStatusCode.OK)
        } else {
            call.respond(HttpStatusCode.BadRequest)
        }
    }

    get("/api/dex/browse") {
        if (!verifyToken(call, deviceConfig)) {
            call.respond(HttpStatusCode.Unauthorized, "Unauthorized")
            return@get
        }

        val path = call.request.queryParameters["path"] ?: "/sdcard/"
        val dir = File(path)
        
        if (!dir.exists() || !dir.isDirectory) {
            call.respond(HttpStatusCode.NotFound, "Directory not found")
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
        if (!verifyToken(call, deviceConfig)) {
            call.respond(HttpStatusCode.Unauthorized, "Unauthorized")
            return@get
        }
        val path = call.request.queryParameters["path"]
        if (path == null) {
            call.respond(HttpStatusCode.BadRequest, "Missing path parameter")
            return@get
        }
        val file = File(path)
        if (!file.exists() || !file.isFile) {
            call.respond(HttpStatusCode.NotFound, "File not found")
            return@get
        }
        
        call.response.header(
            HttpHeaders.ContentDisposition,
            ContentDisposition.Attachment.withParameter(ContentDisposition.Parameters.FileName, file.name).toString()
        )
        call.respondFile(file)
    }
}
