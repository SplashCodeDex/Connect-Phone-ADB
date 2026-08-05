package com.example.dex.network

import org.json.JSONObject

object TokenCodec {
    fun encode(map: Map<String, String>): String {
        val json = JSONObject()
        map.forEach { (k, v) -> json.put(k, v) }
        return json.toString()
    }

    fun decode(raw: String): Map<String, String> {
        val json = JSONObject(raw)
        val result = mutableMapOf<String, String>()
        json.keys().forEach { key -> result[key] = json.getString(key) }
        return result
    }
}