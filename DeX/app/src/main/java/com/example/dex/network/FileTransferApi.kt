package com.example.dex.network

import android.content.Context
import android.content.Intent
import android.net.Uri
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
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

fun verifyToken(call: ApplicationCall, deviceConfig: DeviceConfig): Boolean {
    val authHeader = call.request.header(HttpHeaders.Authorization)
    if (authHeader != null && authHeader.startsWith("Bearer ")) {
        val token = authHeader.removePrefix("Bearer ")
        if (token == deviceConfig.identityHash || AuthState.guestTokens.contains(token) || AuthState.pairedTokens.values.contains(token)) {
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
        
        val accepted = kotlinx.coroutines.withTimeoutOrNull(60_000) { deferred.await() }
        TransferState.pendingPrompts.remove(sessionId)
        if (accepted != true) {
            call.respond(HttpStatusCode.Forbidden)
            return@post
        }

        // If the user hasn't granted the Downloads/DeX folder yet, prompt them and ask sender to retry.
        if (SafStorage.getDownloadsDexUri(context) == null) {
            promptForDownloadsDexGrant(context)
            call.respond(HttpStatusCode.PreconditionFailed, "Downloads/DeX folder grant required — user was prompted, please retry")
            return@post
        }
        
        val responseFiles = mutableMapOf<String, String>()
        for ((fileId, fileMeta) in request.files) {
            responseFiles[fileId] = UUID.randomUUID().toString()
        }
        
        TransferState.activeSessions[sessionId] = request
        // Session cleanup after 10 minutes
        CoroutineScope(Dispatchers.IO).launch {
            kotlinx.coroutines.delay(10 * 60 * 1000)
            TransferState.activeSessions.remove(sessionId)
        }
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
        val dirUri = SafStorage.getDownloadsDexUri(context)
        if (dirUri == null) {
            promptForDownloadsDexGrant(context)
            call.respond(HttpStatusCode.PreconditionFailed, "Downloads/DeX folder grant required")
            return@post
        }

        val out = SafStorage.openOutputStream(context, dirUri, originalFileName)
        if (out == null) {
            call.respond(HttpStatusCode.InternalServerError, "Failed to write file")
            return@post
        }
        val bytes = call.receive<ByteArray>()
        out.write(bytes)
        out.close()
        
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
            val dirUri = SafStorage.getDownloadsDexUri(context)
            if (dirUri == null) {
                promptForDownloadsDexGrant(context)
                call.respond(HttpStatusCode.PreconditionFailed, "Downloads/DeX folder grant required")
                return@post
            }
            TcpDownloadService.download(context, ip, portStr.toInt(), fileId, fileName, fileSize, dirUri)
            call.respond(HttpStatusCode.OK)
        } else {
            call.respond(HttpStatusCode.BadRequest)
        }
    }

    // --- File explorer (opt-in, SAF-granted folders) ---

    get("/api/dex/folders") {
        if (!verifyToken(call, deviceConfig)) {
            call.respond(HttpStatusCode.Unauthorized, "Unauthorized")
            return@get
        }
        val folders = SafStorage.getGrantedFolders(context).map { (name, uri) ->
            mapOf("name" to name, "uri" to uri)
        }
        call.respond(folders)
    }

    post("/api/dex/grant-folder") {
        if (!verifyToken(call, deviceConfig)) {
            call.respond(HttpStatusCode.Unauthorized, "Unauthorized")
            return@post
        }
        val name = call.request.queryParameters["name"] ?: "Folder"
        promptForFolderGrant(context, name)
        call.respond(HttpStatusCode.Accepted, "Folder picker launched")
    }

    get("/api/dex/browse") {
        if (!verifyToken(call, deviceConfig)) {
            call.respond(HttpStatusCode.Unauthorized, "Unauthorized")
            return@get
        }

        val path = call.request.queryParameters["path"] ?: return@get call.respond(HttpStatusCode.BadRequest, "Missing path")
        val treeUri = Uri.parse(path)
        val children = SafStorage.listChildren(context, treeUri)
        call.respond(children)
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
        val docUri = Uri.parse(path)
        val name = docUri.lastPathSegment ?: "file"
        val bytes = SafStorage.readDocumentBytes(context, docUri)
        if (bytes == null) {
            call.respond(HttpStatusCode.NotFound, "File not found")
            return@get
        }
        
        call.response.header(
            HttpHeaders.ContentDisposition,
            ContentDisposition.Attachment.withParameter(ContentDisposition.Parameters.FileName, name).toString()
        )
        call.respondBytes(bytes)
    }
}

private fun promptForDownloadsDexGrant(context: Context) {
    val intent = Intent(context, com.example.dex.MainActivity::class.java).apply {
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        putExtra("REQUEST_DOWNLOADS_DEX_GRANT", true)
    }
    context.startActivity(intent)
}

private fun promptForFolderGrant(context: Context, name: String) {
    val intent = Intent(context, com.example.dex.MainActivity::class.java).apply {
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        putExtra("REQUEST_FOLDER_GRANT", name)
    }
    context.startActivity(intent)
}