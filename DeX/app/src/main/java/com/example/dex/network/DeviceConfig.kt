package com.example.dex.network

import android.content.Context
import android.content.SharedPreferences
import java.security.MessageDigest
import java.util.UUID

class DeviceConfig(context: Context) {
    private val prefs: SharedPreferences = context.getSharedPreferences("dex_prefs", Context.MODE_PRIVATE)

    var email: String
        get() = prefs.getString("email", "") ?: ""
        set(value) {
            prefs.edit().putString("email", value).apply()
            updateIdentityHash(value)
        }

    var fingerprint: String
        get() = prefs.getString("fingerprint", null) ?: UUID.randomUUID().toString().also {
            prefs.edit().putString("fingerprint", it).apply()
        }
        private set(value) {}

    var identityHash: String = ""
        private set

    init {
        updateIdentityHash(email)
    }

    private fun updateIdentityHash(emailStr: String) {
        if (emailStr.isNotBlank()) {
            val bytes = MessageDigest.getInstance("SHA-256").digest(emailStr.trim().lowercase().toByteArray())
            identityHash = bytes.joinToString("") { "%02x".format(it) }
            prefs.edit().putString("identity_hash", identityHash).apply()
        } else {
            val savedHash = prefs.getString("identity_hash", null)
            identityHash = if (savedHash != null && savedHash.contains("-")) {
                savedHash
            } else {
                UUID.randomUUID().toString().also {
                    prefs.edit().putString("identity_hash", it).apply()
                }
            }
        }
    }
}
