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
    val download: Boolean,
    val identityHash: String? = null
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
    val preview: String? = null,
    val partialHash: String? = null
)

@Serializable
data class PrepareUploadResponseDto(
    val sessionId: String,
    val files: Map<String, String>
)

@Serializable
data class BrowseFileDto(
    val name: String,
    val isDirectory: Boolean,
    val size: Long,
    val path: String
)

data class DiscoveredDevice(
    val ip: String,
    val info: RegisterDto,
    val lastSeenTimestamp: Long = System.currentTimeMillis(),
    val trustLevel: String = "Guest"
)
@Serializable
data class PairRequestDto(
    val alias: String,
    val fingerprint: String,
    val pin: String,
    val token: String? = null
)
@Serializable
data class NotifyDownloadDto(
    val ip: String,
    val port: String,
    val fileId: String,
    val fileName: String? = null,
    val fileSize: String? = null
)
