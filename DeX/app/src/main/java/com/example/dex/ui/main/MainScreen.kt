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
import androidx.compose.material.icons.filled.Settings
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
    onNavigateToSettings: () -> Unit = {},
    viewModel: MainScreenViewModel = viewModel(),
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    var selectedDevice by remember { mutableStateOf<DiscoveredDevice?>(null) }

    // Modern Android Photo/File Picker
    val filePickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.GetMultipleContents()
    ) { uris: List<Uri> ->
        if (uris.isEmpty()) return@rememberLauncherForActivityResult
        selectedDevice?.let { device ->
            Toast.makeText(context, "Sending ${uris.size} files to ${device.info.alias}...", Toast.LENGTH_SHORT).show()
            
            scope.launch {
                val fileData = uris.associate { uri ->
                    var name = "shared_file"
                    var size = 0L
                    context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            val nameIdx = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                            val sizeIdx = cursor.getColumnIndex(android.provider.OpenableColumns.SIZE)
                            if (nameIdx >= 0) name = cursor.getString(nameIdx) ?: name
                            if (sizeIdx >= 0) size = cursor.getLong(sizeIdx)
                        }
                    }
                    java.util.UUID.randomUUID().toString() to Triple(uri, name, size)
                }

                val prepareRequest = com.example.dex.network.PrepareUploadRequestDto(
                    info = com.example.dex.network.RegisterDto(
                        alias = "DeX", version = "2.0", deviceModel = "Android",
                        deviceType = "mobile", fingerprint = "dex-fingerprint",
                        port = 53317, protocol = "https", download = true
                    ),
                    files = fileData.mapValues { (id, d) -> com.example.dex.network.FileDto(id, d.second, d.third, "application/octet-stream") }
                )
                
                val response = DexAppContainer.clientEngine.prepareUpload(device.ip, device.info.port, prepareRequest)
                if (response != null) {
                    Log.i("DeX", "UI: Transfer Prepared! SessionId: ${response.sessionId}")
                    var successCount = 0
                    fileData.forEach { (id, d) ->
                        val token = response.files[id] ?: return@forEach
                        context.contentResolver.openInputStream(d.first)?.use { stream ->
                            if (DexAppContainer.clientEngine.uploadFile(device.ip, device.info.port, response.sessionId, id, token, stream, d.third)) {
                                successCount++
                            }
                        }
                    }
                    if (successCount > 0) {
                        Toast.makeText(context, "Uploaded $successCount/${uris.size} files successfully!", Toast.LENGTH_SHORT).show()
                    } else {
                        Toast.makeText(context, "Upload failed for all files.", Toast.LENGTH_SHORT).show()
                    }
                } else {
                    Log.e("DeX", "UI Error: Transfer preparation failed.")
                    Toast.makeText(context, "Transfer preparation failed.", Toast.LENGTH_SHORT).show()
                }
            }
        }
    }

    val downloadState by com.example.dex.network.TcpDownloadService.downloadState.collectAsStateWithLifecycle()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("DeX", fontWeight = FontWeight.Bold) },
                actions = {
                    IconButton(onClick = onNavigateToSettings) {
                        Icon(Icons.Default.Settings, contentDescription = "Settings")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.primaryContainer,
                    titleContentColor = MaterialTheme.colorScheme.onPrimaryContainer
                )
            )
        },
        bottomBar = {
            if (downloadState.isDownloading) {
                Surface(
                    color = MaterialTheme.colorScheme.secondaryContainer,
                    contentColor = MaterialTheme.colorScheme.onSecondaryContainer,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text("Downloading ${downloadState.fileName}...", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                        Spacer(modifier = Modifier.height(8.dp))
                        LinearProgressIndicator(
                            progress = { downloadState.progress },
                            modifier = Modifier.fillMaxWidth(),
                            color = MaterialTheme.colorScheme.primary,
                            trackColor = MaterialTheme.colorScheme.onSecondaryContainer.copy(alpha = 0.2f)
                        )
                        Spacer(modifier = Modifier.height(4.dp))
                        Text("${(downloadState.progress * 100).toInt()}%", style = MaterialTheme.typography.bodySmall)
                    }
                }
            } else if (downloadState.isSuccess) {
                Surface(
                    color = MaterialTheme.colorScheme.primaryContainer,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(
                        "Successfully Downloaded ${downloadState.fileName}", 
                        modifier = Modifier.padding(16.dp), 
                        fontWeight = FontWeight.Bold
                    )
                }
            } else if (downloadState.error != null) {
                Surface(
                    color = MaterialTheme.colorScheme.errorContainer,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(
                        "Download Failed: ${downloadState.error}", 
                        modifier = Modifier.padding(16.dp), 
                        color = MaterialTheme.colorScheme.onErrorContainer
                    )
                }
            }
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
            @Suppress("DEPRECATION")
            Icon(
                imageVector = Icons.Default.Send,
                contentDescription = "Send File",
                tint = MaterialTheme.colorScheme.secondary
            )
        }
    }
}
