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
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import androidx.work.workDataOf
import kotlinx.serialization.json.Json
import kotlinx.serialization.encodeToString

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

    val notificationPermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { _ -> }

    LaunchedEffect(Unit) {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            notificationPermissionLauncher.launch(android.Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    // Modern Android Photo/File Picker
    val filePickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenMultipleDocuments()
    ) { uris: List<Uri> ->
        if (uris.isEmpty()) return@rememberLauncherForActivityResult
        selectedDevice?.let { device ->
            Toast.makeText(context, "Sending ${uris.size} files to ${device.info.alias}...", Toast.LENGTH_SHORT).show()
            
            DexAppContainer.clientEngine.resetUploadState()
            
            val urisJson = try {
                Json.encodeToString(uris.map { it.toString() })
            } catch (e: Exception) {
                e.printStackTrace()
                return@let
            }
            
            val inputData = workDataOf(
                "ip" to device.ip,
                "port" to device.info.port,
                "uris" to urisJson
            )
            
            val workRequest = OneTimeWorkRequestBuilder<com.example.dex.network.UploadWorker>()
                .setInputData(inputData)
                .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                .build()
                
            DexAppContainer.clientEngine.activeWorkId = workRequest.id
            WorkManager.getInstance(context).enqueue(workRequest)
        }
    }

    val downloadState by com.example.dex.network.TcpDownloadService.downloadState.collectAsStateWithLifecycle()
    val uploadState by DexAppContainer.clientEngine.uploadState.collectAsStateWithLifecycle()

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
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text("Downloading...", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                            TextButton(onClick = { com.example.dex.network.TcpDownloadService.cancelDownload(context) }) {
                                Text("Cancel", color = MaterialTheme.colorScheme.error)
                            }
                        }
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(downloadState.fileName, style = MaterialTheme.typography.bodySmall, maxLines = 1)
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
            } else if (uploadState.isUploading) {
                Surface(
                    color = MaterialTheme.colorScheme.secondaryContainer,
                    contentColor = MaterialTheme.colorScheme.onSecondaryContainer,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text("Uploading ${uploadState.currentFileIndex} of ${uploadState.totalFiles} files...", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                            TextButton(onClick = { DexAppContainer.clientEngine.cancelUpload(context) }) {
                                Text("Cancel", color = MaterialTheme.colorScheme.error)
                            }
                        }
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(uploadState.fileName, style = MaterialTheme.typography.bodySmall, maxLines = 1)
                        Spacer(modifier = Modifier.height(8.dp))
                        LinearProgressIndicator(
                            progress = { uploadState.aggregateProgress },
                            modifier = Modifier.fillMaxWidth(),
                            color = MaterialTheme.colorScheme.primary,
                            trackColor = MaterialTheme.colorScheme.onSecondaryContainer.copy(alpha = 0.2f)
                        )
                        Spacer(modifier = Modifier.height(4.dp))
                        Text("${(uploadState.aggregateProgress * 100).toInt()}% Total", style = MaterialTheme.typography.bodySmall)
                    }
                }
            } else if (uploadState.isSuccess) {
                Surface(
                    color = MaterialTheme.colorScheme.primaryContainer,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(
                        "Successfully Uploaded ${uploadState.fileName}", 
                        modifier = Modifier.padding(16.dp), 
                        fontWeight = FontWeight.Bold
                    )
                }
            } else if (uploadState.error != null) {
                Surface(
                    color = MaterialTheme.colorScheme.errorContainer,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(
                        "Upload Failed: ${uploadState.error}", 
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
                            // Open native document picker (Filters to all files)
                            filePickerLauncher.launch(arrayOf("*/*")) 
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
