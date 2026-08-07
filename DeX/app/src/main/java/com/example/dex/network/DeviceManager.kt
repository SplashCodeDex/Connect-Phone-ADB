package com.example.dex.network

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit

object DeviceManager {
    private const val PREFS_NAME = "dex_device_prefs"
    private const val KEY_PAIRED_FINGERPRINTS = "paired_fingerprints"
    private const val KEY_PAIRED_TOKENS = "paired_tokens"

    private lateinit var prefs: SharedPreferences

    fun init(context: Context) {
        prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        loadPairedFingerprints()
        loadPairedTokens()
    }

    private fun loadPairedFingerprints() {
        val saved = prefs.getStringSet(KEY_PAIRED_FINGERPRINTS, emptySet())
        AuthState.pairedFingerprints.clear()
        if (saved != null) {
            AuthState.pairedFingerprints.addAll(saved)
        }
    }

    private fun loadPairedTokens() {
        val saved = prefs.getString(KEY_PAIRED_TOKENS, null) ?: return
        try {
            val map = com.example.dex.network.TokenCodec.decode(saved)
            AuthState.pairedTokens.clear()
            AuthState.pairedTokens.putAll(map)
        } catch (_: Exception) {}
    }

    fun savePairedFingerprint(fingerprint: String) {
        AuthState.pairedFingerprints.add(fingerprint)
        prefs.edit { putStringSet(KEY_PAIRED_FINGERPRINTS, AuthState.pairedFingerprints.toSet()) }
    }

    fun savePairedToken(fingerprint: String, token: String) {
        AuthState.pairedTokens[fingerprint] = token
        prefs.edit { putString(KEY_PAIRED_TOKENS, com.example.dex.network.TokenCodec.encode(AuthState.pairedTokens)) }
    }
    
    fun removePairedFingerprint(fingerprint: String) {
        AuthState.pairedFingerprints.remove(fingerprint)
        AuthState.pairedTokens.remove(fingerprint)
        prefs.edit {
            putStringSet(KEY_PAIRED_FINGERPRINTS, AuthState.pairedFingerprints.toSet())
            putString(KEY_PAIRED_TOKENS, com.example.dex.network.TokenCodec.encode(AuthState.pairedTokens))
        }
    }
}
