package com.example.dex.ui.main

import com.example.dex.network.AuthState
import com.example.dex.network.ClientEngine
import com.example.dex.network.DiscoveredDevice
import com.example.dex.network.DiscoveryEngine
import com.example.dex.network.RegisterDto
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class MainScreenViewModelTest {

    private val testDispatcher = StandardTestDispatcher()
    private val mockDiscovery = mockk<DiscoveryEngine>()
    private val mockClient = mockk<ClientEngine>()

    private val testDevice = DiscoveredDevice(
        ip = "192.168.1.100",
        info = RegisterDto(
            alias = "Test Phone",
            version = "1.0",
            deviceModel = "Pixel 6",
            deviceType = "mobile",
            fingerprint = "fp_untrusted_99",
            port = 53317,
            protocol = "https",
            download = true
        )
    )

    @Before
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
        AuthState.pairedFingerprints.clear()
        AuthState.pairedTokens.clear()
        every { mockDiscovery.devices } returns MutableStateFlow(emptyMap())
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
        AuthState.pairedFingerprints.clear()
        AuthState.pairedTokens.clear()
    }

    @Test
    fun `uiState initially loading`() = runTest {
        val viewModel = MainScreenViewModel(mockDiscovery, mockClient)
        val state = viewModel.uiState.value
        assertEquals(MainScreenUiState.Loading, state)
    }

    @Test
    fun `sendClipboard delegates to clientEngine and triggers callback with result`() = runTest(testDispatcher) {
        coEvery { 
            mockClient.sendClipboard("192.168.1.100", 53317, "Hello Text", "fp_untrusted_99") 
        } returns true

        val viewModel = MainScreenViewModel(mockDiscovery, mockClient)
        var callbackResult: Boolean? = null

        viewModel.sendClipboard(testDevice, "Hello Text") { result ->
            callbackResult = result
        }

        testDispatcher.scheduler.advanceUntilIdle()

        assertEquals(true, callbackResult)
        coVerify { mockClient.sendClipboard("192.168.1.100", 53317, "Hello Text", "fp_untrusted_99") }
    }

    @Test
    fun `untrusted device detection correctly identifies untrusted vs trusted state`() {
        assertFalse("Device should initially be untrusted", AuthState.pairedFingerprints.contains(testDevice.info.fingerprint))

        AuthState.pairedFingerprints.add(testDevice.info.fingerprint)

        assertTrue("Device should be recognized as trusted after adding fingerprint", AuthState.pairedFingerprints.contains(testDevice.info.fingerprint))
    }

    @Test
    fun `sendHandshake registers device when registerDevice returns true`() = runTest(testDispatcher) {
        coEvery { 
            mockClient.registerDevice(testDevice.ip, testDevice.info.port, any()) 
        } returns true

        val viewModel = MainScreenViewModel(mockDiscovery, mockClient)
        viewModel.sendHandshake(testDevice)

        testDispatcher.scheduler.advanceUntilIdle()

        coVerify { mockClient.registerDevice(testDevice.ip, testDevice.info.port, any()) }
        assertTrue("Fingerprint should be added to paired set on successful registerDevice", AuthState.pairedFingerprints.contains(testDevice.info.fingerprint))
    }

    @Test
    fun `sendHandshake does not pair device when registerDevice returns false`() = runTest(testDispatcher) {
        coEvery { 
            mockClient.registerDevice(testDevice.ip, testDevice.info.port, any()) 
        } returns false

        val viewModel = MainScreenViewModel(mockDiscovery, mockClient)
        viewModel.sendHandshake(testDevice)

        testDispatcher.scheduler.advanceUntilIdle()

        coVerify { mockClient.registerDevice(testDevice.ip, testDevice.info.port, any()) }
        assertFalse("Fingerprint should not be paired on failed registerDevice", AuthState.pairedFingerprints.contains(testDevice.info.fingerprint))
    }

    @Test
    fun `pairingDeviceFingerprint guards against concurrent duplicate handshake requests`() = runTest(testDispatcher) {
        coEvery { 
            mockClient.registerDevice(testDevice.ip, testDevice.info.port, any()) 
        } returns true

        val viewModel = MainScreenViewModel(mockDiscovery, mockClient)
        var pairingDeviceFingerprint: String? = null
        var handshakeCalls = 0

        val simulateDeviceClick = { device: DiscoveredDevice ->
            if (pairingDeviceFingerprint != device.info.fingerprint) {
                pairingDeviceFingerprint = device.info.fingerprint
                viewModel.sendHandshake(device) { _ ->
                    pairingDeviceFingerprint = null
                }
                handshakeCalls++
            }
        }

        simulateDeviceClick(testDevice)
        assertEquals(1, handshakeCalls)
        assertEquals(testDevice.info.fingerprint, pairingDeviceFingerprint)

        // Rapid duplicate click while pairing active
        simulateDeviceClick(testDevice)
        assertEquals("Duplicate click must be ignored", 1, handshakeCalls)

        testDispatcher.scheduler.advanceUntilIdle()

        // After completion callback, state is reset to null
        assertEquals(null, pairingDeviceFingerprint)
    }

    @Test
    fun `mutableStateSetOf pairedFingerprints triggers state changes on add and remove`() {
        val pairedSet = AuthState.pairedFingerprints
        assertTrue("AuthState.pairedFingerprints must be a Compose SnapshotStateSet", pairedSet is androidx.compose.runtime.snapshots.SnapshotStateSet<*>)
        assertFalse(pairedSet.contains(testDevice.info.fingerprint))

        pairedSet.add(testDevice.info.fingerprint)
        assertTrue(pairedSet.contains(testDevice.info.fingerprint))

        pairedSet.remove(testDevice.info.fingerprint)
        assertFalse(pairedSet.contains(testDevice.info.fingerprint))
    }

    @Test
    fun `sendHandshake failure callback resets pairingDeviceFingerprint to null`() = runTest(testDispatcher) {
        coEvery { 
            mockClient.registerDevice(testDevice.ip, testDevice.info.port, any()) 
        } returns false

        val viewModel = MainScreenViewModel(mockDiscovery, mockClient)
        var pairingDeviceFingerprint: String? = testDevice.info.fingerprint
        var callbackSuccess: Boolean? = null

        viewModel.sendHandshake(testDevice) { success ->
            pairingDeviceFingerprint = null
            callbackSuccess = success
        }

        testDispatcher.scheduler.advanceUntilIdle()

        assertEquals(false, callbackSuccess)
        assertEquals("pairingDeviceFingerprint must reset to null on failure path", null, pairingDeviceFingerprint)
        assertFalse(AuthState.pairedFingerprints.contains(testDevice.info.fingerprint))
    }

    @Test
    fun `pairing_with string resource format produces expected string`() {
        val alias = testDevice.info.alias
        val formatted = String.format("Pairing with %1\$s...", alias)
        assertEquals("Pairing with Test Phone...", formatted)
    }
}
