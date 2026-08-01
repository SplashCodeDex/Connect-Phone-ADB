package com.example.dex.network

object DexAppContainer {
    var context: android.content.Context? = null
    val discoveryEngine = DiscoveryEngine()
    val restServerEngine = RestServerEngine()
    val clientEngine = ClientEngine()
    
    var identityHash: String = ""
    var fingerprint: String = ""

    fun initialize(ctx: android.content.Context) {
        context = ctx.applicationContext
        val prefs = ctx.getSharedPreferences("dex_prefs", android.content.Context.MODE_PRIVATE)
        identityHash = prefs.getString("identity_hash", null) ?: java.util.UUID.randomUUID().toString().also {
            prefs.edit().putString("identity_hash", it).apply()
        }
        fingerprint = prefs.getString("fingerprint", null) ?: java.util.UUID.randomUUID().toString().also {
            prefs.edit().putString("fingerprint", it).apply()
        }
    }
}
