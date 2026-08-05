package com.example.dex.network

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.SharedPreferencesMigration
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import timber.log.Timber
import java.security.MessageDigest
import java.util.UUID

val Context.dataStore: DataStore<Preferences> by preferencesDataStore(
    name = "dex_datastore",
    produceMigrations = { context ->
        listOf(SharedPreferencesMigration(context, "dex_prefs"))
    }
)

class DeviceConfig(private val context: Context) {
    private val scope = CoroutineScope(Dispatchers.IO)

    companion object {
        val EMAIL_KEY = stringPreferencesKey("email")
        val FINGERPRINT_KEY = stringPreferencesKey("fingerprint")
        val IDENTITY_HASH_KEY = stringPreferencesKey("identity_hash")
    }

    private val _emailFlow = MutableStateFlow("")
    val emailFlow: StateFlow<String> = _emailFlow.asStateFlow()

    private val _fingerprintFlow = MutableStateFlow("")
    val fingerprintFlow: StateFlow<String> = _fingerprintFlow.asStateFlow()

    private val _identityHashFlow = MutableStateFlow("")
    val identityHashFlow: StateFlow<String> = _identityHashFlow.asStateFlow()

    var email: String
        get() = _emailFlow.value
        set(value) {
            _emailFlow.value = value
            updateIdentityHash(value)
            scope.launch {
                Timber.d("Saving new email to DataStore: %s", value)
                context.dataStore.edit { prefs ->
                    prefs[EMAIL_KEY] = value
                }
            }
        }

    val fingerprint: String
        get() = _fingerprintFlow.value

    val identityHash: String
        get() = _identityHashFlow.value

    init {
        // Run blocking just for the very first initialization to ensure memory cache is primed 
        // before Ktor tries to read the fingerprint and binds to ports.
        // It's IO dispatched so it doesn't hard-block the UI strictly if we do it cleanly,
        // but here we just block the Koin initialization momentarily.
        runBlocking(Dispatchers.IO) {
            Timber.i("Initializing DeviceConfig from DataStore...")
            val prefs = context.dataStore.data.first()

            val savedEmail = prefs[EMAIL_KEY] ?: ""
            _emailFlow.value = savedEmail

            var savedFingerprint = prefs[FINGERPRINT_KEY]
            if (savedFingerprint == null) {
                savedFingerprint = UUID.randomUUID().toString()
                context.dataStore.edit { it[FINGERPRINT_KEY] = savedFingerprint }
                Timber.d("Generated new device fingerprint: %s", savedFingerprint)
            }
            _fingerprintFlow.value = savedFingerprint

            updateIdentityHashInternal(savedEmail, prefs[IDENTITY_HASH_KEY])
            Timber.i("DeviceConfig fully initialized.")
        }
    }

    private suspend fun updateIdentityHashInternal(emailStr: String, savedHash: String?) {
        if (emailStr.isNotBlank()) {
            val bytes = MessageDigest.getInstance("SHA-256").digest(emailStr.trim().lowercase().toByteArray())
            val newHash = bytes.joinToString("") { "%02x".format(it) }
            _identityHashFlow.value = newHash
            context.dataStore.edit { it[IDENTITY_HASH_KEY] = newHash }
        } else {
            val newHash = if (savedHash != null) {
                savedHash
            } else {
                val generated = UUID.randomUUID().toString()
                context.dataStore.edit { it[IDENTITY_HASH_KEY] = generated }
                generated
            }
            _identityHashFlow.value = newHash
        }
        Timber.d("Identity hash updated: %s", _identityHashFlow.value)
    }

    private fun updateIdentityHash(emailStr: String) {
        scope.launch {
            val prefs = context.dataStore.data.first()
            updateIdentityHashInternal(emailStr, prefs[IDENTITY_HASH_KEY])
        }
    }
}
