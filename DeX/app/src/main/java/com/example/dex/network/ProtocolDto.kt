package com.example.dex.network

import kotlinx.serialization.Serializable

@Serializable
data class RegisterDto(
    val alias: String,
    val version: String,
    val deviceModel: String,
    val deviceType: String,
    val fingerprint: String,
    val port: Int,
    val protocol: String,
    val download: Boolean
)

@Serializable
data class PrepareUploadRequestDto(
    val info: RegisterDto,
    val files: Map<String, FileDto>
)

@Serializable
data class FileDto(
    val id: String,
    val fileName: String,
    val size: Long,
    val fileType: String,
    val sha256: String? = null,
    val preview: String? = null
)

@Serializable
data class PrepareUploadResponseDto(
    val sessionId: String,
    val files: Map<String, String>
)
