package com.example.dex.network

import android.content.Context
import android.content.SharedPreferences
import io.mockk.every
import io.mockk.mockk
import io.mockk.mockkObject
import io.mockk.slot
import io.mockk.unmockkObject
import io.mockk.verify
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class DeviceManagerTest {

    private val mockContext = mockk<Context>()
    private val mockPrefs = mockk<SharedPreferences>(relaxed = true)
    private val mockEditor = mockk<SharedPreferences.Editor>(relaxed = true)

    @Before
    fun setUp() {
        mockkObject(TokenCodec)
        every { TokenCodec.encode(any()) } returns """{"fp":"token"}"""
        every { TokenCodec.decode(any()) } returns emptyMap()

        AuthState.pairedFingerprints.clear()
        AuthState.pairedTokens.clear()

        every { mockContext.getSharedPreferences("dex_device_prefs", Context.MODE_PRIVATE) } returns mockPrefs
        every { mockPrefs.edit() } returns mockEditor
        every { mockEditor.putStringSet(any(), any()) } returns mockEditor
        every { mockEditor.putString(any(), any()) } returns mockEditor

        DeviceManager.init(mockContext)
    }

    @After
    fun tearDown() {
        unmockkObject(TokenCodec)
        AuthState.pairedFingerprints.clear()
        AuthState.pairedTokens.clear()
    }

    @Test
    fun `savePairedFingerprint adds fingerprint to AuthState and persists to SharedPreferences`() {
        val fingerprint = "fp_alpha_123"

        DeviceManager.savePairedFingerprint(fingerprint)

        assertTrue(AuthState.pairedFingerprints.contains(fingerprint))

        val capturedSet = slot<Set<String>>()
        verify { mockEditor.putStringSet("paired_fingerprints", capture(capturedSet)) }
        assertTrue(capturedSet.captured.contains(fingerprint))
    }

    @Test
    fun `removePairedFingerprint removes fingerprint and paired token from AuthState and SharedPreferences`() {
        val fingerprint = "fp_target_456"
        val token = "token_target_456"

        AuthState.pairedFingerprints.add(fingerprint)
        AuthState.pairedTokens[fingerprint] = token

        DeviceManager.removePairedFingerprint(fingerprint)

        assertFalse(AuthState.pairedFingerprints.contains(fingerprint))
        assertFalse(AuthState.pairedTokens.containsKey(fingerprint))

        val capturedSet = slot<Set<String>>()
        verify { mockEditor.putStringSet("paired_fingerprints", capture(capturedSet)) }
        assertFalse(capturedSet.captured.contains(fingerprint))

        val capturedTokenString = slot<String>()
        verify { mockEditor.putString("paired_tokens", capture(capturedTokenString)) }
    }

    @Test
    fun `savePairedToken adds token to AuthState and updates SharedPreferences`() {
        val fingerprint = "fp_token_789"
        val token = "token_val_789"

        DeviceManager.savePairedToken(fingerprint, token)

        assertEquals(token, AuthState.pairedTokens[fingerprint])

        val capturedTokenString = slot<String>()
        verify { mockEditor.putString("paired_tokens", capture(capturedTokenString)) }
    }

    @Test
    fun `init loads pre-existing fingerprints from SharedPreferences`() {
        val existingFingerprints = setOf("fp_stored_1", "fp_stored_2")
        every { mockPrefs.getStringSet("paired_fingerprints", emptySet()) } returns existingFingerprints

        DeviceManager.init(mockContext)

        assertEquals(2, AuthState.pairedFingerprints.size)
        assertTrue(AuthState.pairedFingerprints.contains("fp_stored_1"))
        assertTrue(AuthState.pairedFingerprints.contains("fp_stored_2"))
    }
}
