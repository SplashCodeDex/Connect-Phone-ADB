package com.example.dex.network

import kotlinx.coroutines.CompletableDeferred
import java.util.concurrent.ConcurrentHashMap

object TransferState {
    val pendingPrompts = ConcurrentHashMap<String, CompletableDeferred<Boolean>>()
    val activeSessions = ConcurrentHashMap<String, PrepareUploadRequestDto>()
}

object AuthState {
    val guestTokens = mutableSetOf<String>()
    val currentPairingPin = kotlinx.coroutines.flow.MutableStateFlow<String?>(null)
}
