package com.example.dex.network

import io.ktor.client.*
import io.ktor.client.call.*
import io.ktor.client.engine.cio.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.client.request.*
import io.ktor.http.*
import io.ktor.serialization.kotlinx.json.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.security.cert.X509Certificate
import javax.net.ssl.X509TrustManager
import java.io.InputStream
import io.ktor.utils.io.jvm.javaio.toByteReadChannel

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

    suspend fun uploadFile(ip: String, port: Int, sessionId: String, fileId: String, token: String, content: InputStream): Boolean = withContext(Dispatchers.IO) {
        try {
            val response = client.post("https://$ip:$port/api/localsend/v2/upload") {
                url {
                    parameters.append("sessionId", sessionId)
                    parameters.append("fileId", fileId)
                    parameters.append("token", token)
                }
                setBody(content.toByteReadChannel())
            }
            response.status.isSuccess()
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }
}
