package com.example.dex.ui.main

import android.net.Uri
import android.util.Log
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Computer
import androidx.compose.material.icons.filled.Send
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.example.dex.network.DiscoveredDevice
import com.example.dex.network.DexAppContainer
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen(
    viewModel: MainScreenViewModel = viewModel(),
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    var selectedDevice by remember { mutableStateOf<DiscoveredDevice?>(null) }

    // Modern Android Photo/File Picker
    val filePickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.GetContent()
    ) { uri: Uri? ->
        uri?.let { selectedUri ->
            selectedDevice?.let { device ->
                Toast.makeText(context, "Sending to ${device.info.alias}...", Toast.LENGTH_SHORT).show()
                // Hooking into LocalSend client engine
                scope.launch {
                    val prepareRequest = com.example.dex.network.PrepareUploadRequestDto(
                        info = com.example.dex.network.RegisterDto(
                            alias = "DeX", version = "2.0", deviceModel = "Android",
                            deviceType = "mobile", fingerprint = "dex-fingerprint",
                            port = 53317, protocol = "https", download = true
                        ),
                        files = mapOf("file1" to com.example.dex.network.FileDto("file1", "shared_file", 1024, "application/octet-stream"))
                    )
                    
                    val response = DexAppContainer.clientEngine.prepareUpload(device.ip, device.info.port, prepareRequest)
                    if (response != null) {
                        Log.i("DeX", "UI: Transfer Prepared! SessionId: ${response.sessionId}")
                        
                        val token = response.files["file1"] ?: ""
                        val bytes = context.contentResolver.openInputStream(selectedUri)?.readBytes() ?: ByteArray(0)
                        val success = DexAppContainer.clientEngine.uploadFile(device.ip, device.info.port, response.sessionId, "file1", token, bytes)
                        if (success) {
                            Log.i("DeX", "UI: File uploaded successfully!")
                            Toast.makeText(context, "Upload Success!", Toast.LENGTH_SHORT).show()
                        } else {
                            Log.e("DeX", "UI Error: File upload failed.")
                        }
                    } else {
                        Log.e("DeX", "UI Error: Transfer preparation failed.")
                    }
                }
            }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("DeX", fontWeight = FontWeight.Bold) },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.primaryContainer,
                    titleContentColor = MaterialTheme.colorScheme.onPrimaryContainer
                )
            )
        }
    ) { padding ->
        Column(
            modifier = modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            Text(
                "Nearby Devices",
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.padding(bottom = 16.dp)
            )

            val devices = (uiState as? MainScreenUiState.Success)?.data ?: emptyList()
            if (devices.isEmpty()) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text("Scanning for DeX peers...", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            } else {
                LazyColumn(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    items(devices) { device ->
                        DeviceCard(device = device, onClick = {
                            selectedDevice = device
                            // Open native file picker (Filters to all files)
                            filePickerLauncher.launch("*/*") 
                        })
                    }
                }
            }
        }
    }
}

@Composable
fun DeviceCard(device: DiscoveredDevice, onClick: () -> Unit) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onClick() },
        shape = RoundedCornerShape(16.dp),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .size(48.dp)
                    .clip(CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.Computer,
                    contentDescription = "Device",
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(28.dp)
                )
            }
            Spacer(modifier = Modifier.width(16.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(text = device.info.alias, fontWeight = FontWeight.SemiBold, style = MaterialTheme.typography.bodyLarge)
                Text(text = "${device.ip}:${device.info.port}", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Icon(
                imageVector = Icons.Default.Send,
                contentDescription = "Send File",
                tint = MaterialTheme.colorScheme.secondary
            )
        }
    }
}
