package com.example.dex.network

import java.security.MessageDigest

object DexAppContainer {
    var context: android.content.Context? = null
    val discoveryEngine = DiscoveryEngine()
    val restServerEngine = RestServerEngine()
    val clientEngine = ClientEngine()
    
    var identityHash: String = ""
        private set
    var fingerprint: String = ""
        private set
    var email: String = ""
        private set

    fun initialize(ctx: android.content.Context) {
        context = ctx.applicationContext
        val prefs = ctx.getSharedPreferences("dex_prefs", android.content.Context.MODE_PRIVATE)
        email = prefs.getString("email", "") ?: ""
        fingerprint = prefs.getString("fingerprint", null) ?: java.util.UUID.randomUUID().toString().also {
            prefs.edit().putString("fingerprint", it).apply()
        }
        updateIdentityHash(email, prefs)
    }

    fun setEmail(newEmail: String) {
        email = newEmail
        context?.let { ctx ->
            val prefs = ctx.getSharedPreferences("dex_prefs", android.content.Context.MODE_PRIVATE)
            prefs.edit().putString("email", email).apply()
            updateIdentityHash(email, prefs)
        }
    }

    private fun updateIdentityHash(emailStr: String, prefs: android.content.SharedPreferences) {
        val oldHash = identityHash
        if (emailStr.isNotBlank()) {
            val bytes = MessageDigest.getInstance("SHA-256").digest(emailStr.trim().lowercase().toByteArray())
            identityHash = bytes.joinToString("") { "%02x".format(it) }
            prefs.edit().putString("identity_hash", identityHash).apply()
        } else {
            val savedHash = prefs.getString("identity_hash", null)
            // If the saved hash looks like a UUID, keep it. Otherwise (if it was an email hash), clear it and make a new UUID.
            if (savedHash != null && savedHash.contains("-")) {
                identityHash = savedHash
            } else {
                identityHash = java.util.UUID.randomUUID().toString().also {
                    prefs.edit().putString("identity_hash", it).apply()
                }
            }
        }
        
        if (oldHash != "" && oldHash != identityHash) {
            discoveryEngine.stopDiscovery()
            context?.let { discoveryEngine.startDiscovery(it) }
        }
    }
}
