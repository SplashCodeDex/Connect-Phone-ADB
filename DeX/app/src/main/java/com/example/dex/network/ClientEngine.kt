package com.example.dex.network

import io.ktor.client.*
import io.ktor.client.call.*
import io.ktor.client.engine.cio.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.client.request.*
import io.ktor.http.*
import io.ktor.serialization.kotlinx.json.*
import io.ktor.utils.io.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.security.cert.X509Certificate
import javax.net.ssl.X509TrustManager

import kotlinx.coroutines.Job
import io.ktor.client.plugins.onUpload

class ClientEngine {
    // LocalSend uses self-signed certificates, so we must trust all certificates on the local network
    private val trustAllManager = object : X509TrustManager {
        override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) {}
        override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {}
        override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
    }

    private val client = HttpClient(CIO) {
        install(ContentNegotiation) {
            json()
        }
        engine {
            https {
                trustManager = trustAllManager
            }
        }
    }

    private val _uploadState = MutableStateFlow(UploadState())
    val uploadState = _uploadState.asStateFlow()
    
    var activeWorkId: java.util.UUID? = null

    fun resetUploadState() {
        _uploadState.value = UploadState()
    }
    
    fun finishUpload(successCount: Int, totalFiles: Int) {
        if (successCount > 0) {
            _uploadState.value = _uploadState.value.copy(
                isUploading = false,
                isSuccess = true,
                fileName = "$successCount of $totalFiles files"
            )
        } else {
            _uploadState.value = _uploadState.value.copy(
                isUploading = false,
                error = "Upload failed for all files"
            )
        }
    }
    
    fun cancelUpload(context: android.content.Context) {
        activeWorkId?.let { 
            androidx.work.WorkManager.getInstance(context).cancelWorkById(it) 
        }
        activeWorkId = null
        _uploadState.value = _uploadState.value.copy(
            isUploading = false,
            error = "Upload cancelled"
        )
    }

    suspend fun registerDevice(ip: String, port: Int, info: RegisterDto): Boolean = withContext(Dispatchers.IO) {
        try {
            val response = client.post("https://$ip:$port/api/localsend/v2/register") {
                contentType(ContentType.Application.Json)
                setBody(info)
            }
            response.status.isSuccess()
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }
    
    suspend fun prepareUpload(ip: String, port: Int, request: PrepareUploadRequestDto): PrepareUploadResponseDto? = withContext(Dispatchers.IO) {
        try {
            val response = client.post("https://$ip:$port/api/localsend/v2/prepare-upload") {
                contentType(ContentType.Application.Json)
                setBody(request)
            }
            if (response.status.isSuccess()) {
                response.body<PrepareUploadResponseDto>()
            } else null
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    suspend fun uploadFile(
        ip: String, port: Int, sessionId: String, fileId: String, fileName: String, 
        token: String, stream: java.io.InputStream, fileSize: Long,
        fileIndex: Int = 1, totalFiles: Int = 1,
        previousBatchBytes: Long = 0L, totalBatchSize: Long = fileSize,
        onProgress: suspend (Float) -> Unit = {}
    ): Boolean = withContext(Dispatchers.IO) {
        try {
            val startAggregate = if (totalBatchSize > 0) previousBatchBytes.toFloat() / totalBatchSize else 0f
            _uploadState.value = UploadState(
                fileName = fileName, currentFileIndex = fileIndex, totalFiles = totalFiles,
                progress = 0f, aggregateProgress = startAggregate,
                isUploading = true
            )
            onProgress(startAggregate)
            
            val response = client.post("https://$ip:$port/api/localsend/v2/upload") {
                url {
                    parameters.append("sessionId", sessionId)
                    parameters.append("fileId", fileId)
                    parameters.append("token", token)
                }
                onUpload { bytesSentTotal, _ ->
                    val currentProgress = if (fileSize > 0) bytesSentTotal.toFloat() / fileSize else 0f
                    val aggregate = if (totalBatchSize > 0) (previousBatchBytes + bytesSentTotal).toFloat() / totalBatchSize else 0f
                    
                    _uploadState.value = UploadState(
                        fileName = fileName,
                        currentFileIndex = fileIndex,
                        totalFiles = totalFiles,
                        progress = currentProgress,
                        aggregateProgress = aggregate,
                        isUploading = true
                    )
                    onProgress(aggregate)
                }
                setBody(object : io.ktor.http.content.OutgoingContent.WriteChannelContent() {
                    override val contentType = io.ktor.http.ContentType.Application.OctetStream
                    override val contentLength = fileSize
                    override suspend fun writeTo(channel: io.ktor.utils.io.ByteWriteChannel) {
                        withContext(Dispatchers.IO) {
                            val buffer = ByteArray(81920)
                            var bytesRead = stream.read(buffer)
                            while (bytesRead != -1) {
                                channel.writeFully(buffer, 0, bytesRead)
                                bytesRead = stream.read(buffer)
                            }
                            stream.close()
                            channel.flush()
                        }
                    }
                })
            }
            val success = response.status.isSuccess()
            if (!success) {
                _uploadState.value = _uploadState.value.copy(error = "HTTP ${response.status.value}")
            }
            success
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e // Let the cancellation bubble up
        } catch (e: Exception) {
            e.printStackTrace()
            _uploadState.value = _uploadState.value.copy(error = e.message)
            false
        }
    }
}

data class UploadState(
    val fileName: String = "",
    val currentFileIndex: Int = 1,
    val totalFiles: Int = 1,
    val progress: Float = 0f,
    val aggregateProgress: Float = 0f,
    val isUploading: Boolean = false,
    val isSuccess: Boolean = false,
    val error: String? = null
)
