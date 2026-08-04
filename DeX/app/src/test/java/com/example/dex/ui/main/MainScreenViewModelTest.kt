package com.example.dex.ui.main

import com.example.dex.network.ClientEngine
import com.example.dex.network.DiscoveryEngine
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

class MainScreenViewModelTest {

    @Test
    fun `uiState initially loading`() = runTest {
        val mockDiscovery = mockk<DiscoveryEngine>()
        val mockClient = mockk<ClientEngine>()
        
        every { mockDiscovery.devices } returns MutableStateFlow(emptyMap())

        val viewModel = MainScreenViewModel(mockDiscovery, mockClient)
        
        // At start it could be loading or immediately evaluate to success if flow returns instantly
        // In this architecture, an empty map gives an empty success state
        val state = viewModel.uiState.value
        assertEquals(MainScreenUiState.Loading, state)
    }
}
