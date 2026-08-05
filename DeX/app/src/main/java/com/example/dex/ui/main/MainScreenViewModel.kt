package com.example.dex.ui.main

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.dex.network.ClientEngine
import com.example.dex.network.DiscoveryEngine
import com.example.dex.network.DiscoveredDevice
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class MainScreenViewModel(
    val discoveryEngine: DiscoveryEngine,
    val clientEngine: ClientEngine
) : ViewModel() {
  val uiState: StateFlow<MainScreenUiState> =
    discoveryEngine.devices
      .map<Map<String, DiscoveredDevice>, MainScreenUiState> { devicesMap -> MainScreenUiState.Success(devicesMap.values.toList()) }
      .catch { emit(MainScreenUiState.Error(it)) }
      .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), MainScreenUiState.Loading)
      
  fun sendHandshake(device: DiscoveredDevice) {
      // Intended for future logic where we launch ClientEngine to send files or handshake
  }
  
  fun sendClipboard(device: DiscoveredDevice, text: String, onResult: (Boolean) -> Unit) {
      viewModelScope.launch {
          val success = clientEngine.sendClipboard(device.ip, device.info.port, text, device.info.fingerprint)
          onResult(success)
      }
  }
}

sealed interface MainScreenUiState {
  object Loading : MainScreenUiState
  data class Error(val throwable: Throwable) : MainScreenUiState
  data class Success(val data: List<DiscoveredDevice>) : MainScreenUiState
}
