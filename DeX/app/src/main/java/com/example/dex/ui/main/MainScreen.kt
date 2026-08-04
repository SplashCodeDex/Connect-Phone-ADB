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
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material3.*
import androidx.compose.runtime.*
import com.example.dex.R
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.example.dex.network.DiscoveredDevice
import kotlinx.coroutines.launch
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import androidx.work.workDataOf
import kotlinx.serialization.json.Json
import kotlinx.serialization.encodeToString
import androidx.compose.material3.BasicAlertDialog
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.ui.unit.sp

import org.koin.androidx.compose.koinViewModel
import com.example.dex.ui.components.DeviceListItem
import com.example.dex.ui.components.NetworkErrorDialog
import com.example.dex.ui.components.PairingRequestDialog
import com.example.dex.ui.components.TransferProgressOverlay

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen(
    onNavigateToSettings: () -> Unit = {},
    viewModel: MainScreenViewModel = koinViewModel(),
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
    
    val currentPairingPin by com.example.dex.network.AuthState.currentPairingPin.collectAsStateWithLifecycle()

    val launchQrScanner = {
        val options = com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions.Builder()
            .setBarcodeFormats(com.google.mlkit.vision.barcode.common.Barcode.FORMAT_QR_CODE)
            .enableAutoZoom()
            .build()
        val scanner = com.google.mlkit.vision.codescanner.GmsBarcodeScanning.getClient(context, options)
        scanner.startScan()
            .addOnSuccessListener { barcode ->
                val rawValue = barcode.rawValue
                if (rawValue != null && rawValue.startsWith("http://")) {
                    val uri = Uri.parse(rawValue)
                    val ip = uri.host
                    if (ip != null) {
                        Toast.makeText(context, context.getString(R.string.toast_scanned_ip, ip), Toast.LENGTH_SHORT).show()
                        viewModel.discoveryEngine.sendManualDiscovery(ip)
                    }
                }
            }
            .addOnFailureListener { e ->
                Toast.makeText(context, context.getString(R.string.toast_scan_failed, e.message.toString()), Toast.LENGTH_SHORT).show()
            }
    }

    // Modern Android Photo/File Picker
    val filePickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenMultipleDocuments()
    ) { uris: List<Uri> ->
        if (uris.isEmpty()) return@rememberLauncherForActivityResult
        selectedDevice?.let { device ->
            Toast.makeText(context, context.getString(R.string.toast_sending_files, uris.size, device.info.alias), Toast.LENGTH_SHORT).show()
            
            viewModel.clientEngine.resetUploadState()
            
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
                
            viewModel.clientEngine.activeWorkId = workRequest.id
            WorkManager.getInstance(context).enqueue(workRequest)
        }
    }

    val downloadState by com.example.dex.network.TcpDownloadService.downloadState.collectAsStateWithLifecycle()
    val uploadState by viewModel.clientEngine.uploadState.collectAsStateWithLifecycle()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.app_name), fontWeight = FontWeight.Bold) },
                actions = {
                    IconButton(onClick = { launchQrScanner() }) {
                        Icon(Icons.Default.Computer, contentDescription = stringResource(R.string.scan_qr))
                    }
                    IconButton(onClick = onNavigateToSettings) {
                        Icon(Icons.Default.Settings, contentDescription = stringResource(R.string.settings))
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.primaryContainer,
                    titleContentColor = MaterialTheme.colorScheme.onPrimaryContainer
                )
            )
        },
        bottomBar = {
            TransferProgressOverlay(
                downloadState = downloadState,
                uploadState = uploadState,
                onCancelDownload = { com.example.dex.network.TcpDownloadService.cancelDownload(context) },
                onCancelUpload = { viewModel.clientEngine.cancelUpload(context) }
            )
        }
    ) { padding ->
        Column(
            modifier = modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            Text(
                stringResource(R.string.nearby_devices),
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.padding(bottom = 16.dp)
            )

            val devices = (uiState as? MainScreenUiState.Success)?.data ?: emptyList()
            if (devices.isEmpty()) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(stringResource(R.string.scanning_peers), color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            } else {
                LazyColumn(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    items(devices, key = { it.info.fingerprint }) { device ->
                        DeviceListItem(
                            modifier = Modifier.animateItem(),
                            device = device, 
                            onClick = {
                                selectedDevice = device
                                filePickerLauncher.launch(arrayOf("*/*")) 
                            }, 
                            onSendClipboard = { text ->
                            viewModel.sendClipboard(device, text) { success ->
                                if (success) Toast.makeText(context, context.getString(R.string.clipboard_sent_success), Toast.LENGTH_SHORT).show()
                                else Toast.makeText(context, context.getString(R.string.clipboard_sent_failed), Toast.LENGTH_SHORT).show()
                            }
                        })
                    }
                }
            }
        }
    }
    
    if (uploadState.error != null) {
        NetworkErrorDialog(
            error = stringResource(R.string.upload_failed, uploadState.error ?: ""),
            onDismiss = { viewModel.clientEngine.resetUploadState() }
        )
    }
    
    if (downloadState.error != null) {
        NetworkErrorDialog(
            error = stringResource(R.string.download_failed, downloadState.error ?: ""),
            onDismiss = { com.example.dex.network.TcpDownloadService.resetDownloadState() }
        )
    }
    
    currentPairingPin?.let { pin ->
        PairingRequestDialog(
            pin = pin,
            onDismiss = { com.example.dex.network.AuthState.currentPairingPin.value = null },
            onScanInstead = { launchQrScanner() }
        )
    }
}


