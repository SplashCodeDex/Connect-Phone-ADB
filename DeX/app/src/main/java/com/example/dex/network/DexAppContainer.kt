package com.example.dex.network

object DexAppContainer {
    var context: android.content.Context? = null
    val discoveryEngine = DiscoveryEngine()
    val restServerEngine = RestServerEngine()
    val clientEngine = ClientEngine()
}
