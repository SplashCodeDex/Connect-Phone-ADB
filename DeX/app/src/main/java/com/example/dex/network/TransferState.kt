package com.example.dex.network

import kotlinx.coroutines.CompletableDeferred
import java.util.concurrent.ConcurrentHashMap

object TransferState {
    val pendingPrompts = ConcurrentHashMap<String, CompletableDeferred<Boolean>>()
    val activeSessions = ConcurrentHashMap<String, PrepareUploadRequestDto>()
}

data class PairRequestInfo(
    val alias: String,
    val fingerprint: String,
    val pin: String,
    val deferred: CompletableDeferred<Boolean>
)

object AuthState {
    val guestTokens = mutableSetOf<String>()
    val pairedFingerprints = mutableSetOf<String>()
    val pairedTokens = mutableMapOf<String, String>()
    val incomingPairRequest = kotlinx.coroutines.flow.MutableStateFlow<PairRequestInfo?>(null)
}