package com.example.dex.ui.main

import android.net.Uri
import androidx.core.net.toUri
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.background
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.res.vectorResource
import androidx.compose.ui.graphics.vector.ImageVector
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
import com.example.dex.network.AuthState
import com.example.dex.network.DiscoveredDevice
import kotlinx.coroutines.launch
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import androidx.work.workDataOf
import kotlinx.serialization.json.Json
import kotlinx.serialization.encodeToString

import androidx.compose.ui.unit.sp

import org.koin.androidx.compose.koinViewModel
import com.example.dex.ui.components.DeviceListItem
import com.example.dex.ui.components.NetworkErrorDialog
import com.example.dex.ui.components.PairingRequestDialog
import com.example.dex.ui.components.TransferProgressOverlay
import com.example.dex.ui.components.FloatingTopAppBar
import com.example.dex.ui.components.*
import androidx.compose.ui.text.style.TextAlign

@android.annotation.SuppressLint("LocalContextGetResourceValueCall")
@OptIn(ExperimentalMaterial3Api::class, ExperimentalAnimationApi::class)
@Composable
fun MainScreen(
    modifier: Modifier = Modifier,
    viewModel: MainScreenViewModel = koinViewModel()
) {
    val context = LocalContext.current
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    var selectedDevice by remember { mutableStateOf<DiscoveredDevice?>(null) }
    var pairingDeviceFingerprint by remember { mutableStateOf<String?>(null) }
    var showTroubleshootDialog by remember { mutableStateOf(false) }
    var showTrustedDevicesDialog by remember { mutableStateOf(false) }

    val notificationPermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { _ -> }

    LaunchedEffect(Unit) {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            notificationPermissionLauncher.launch(android.Manifest.permission.POST_NOTIFICATIONS)
        }
    }



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
                    val uri = rawValue.toUri()
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
            Toast.makeText(context, context.resources.getQuantityString(R.plurals.toast_sending_files, uris.size, uris.size, device.info.alias), Toast.LENGTH_SHORT).show()

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
                "uris" to urisJson,
                "targetFingerprint" to device.info.fingerprint
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
        containerColor = MaterialTheme.colorScheme.background,
        floatingActionButton = {
            val devices = (uiState as? MainScreenUiState.Success)?.data ?: emptyList()
            if (devices.isNotEmpty()) {
                DeXFloatingActionButton(
                    onClick = { launchQrScanner() },
                    containerColor = MaterialTheme.colorScheme.primary,
                    contentColor = MaterialTheme.colorScheme.onPrimary,
                    shape = CircleShape,
                    modifier = Modifier.padding(bottom = 88.dp) // Clear the bottom nav bar
                ) {
                    Icon(ImageVector.vectorResource(R.drawable.ic_qr_code_scanner), contentDescription = stringResource(R.string.scan_qr))
                }
            }
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
        ) {
            FloatingTopAppBar(
                onOpenTrustedDevices = { showTrustedDevicesDialog = true }
            )

            val devices = (uiState as? MainScreenUiState.Success)?.data ?: emptyList()

            Box(modifier = Modifier.fillMaxSize().padding(padding)) {
                androidx.compose.animation.AnimatedVisibility(
                    visible = devices.isEmpty(),
                    enter = com.example.dex.ui.theme.spatialMenuEnter(),
                    exit = com.example.dex.ui.theme.spatialMenuExit(),
                    modifier = Modifier.align(Alignment.Center).padding(bottom = 88.dp)
                ) {
                    DeXPanel(
                        shape = RoundedCornerShape(32.dp),
                        modifier = Modifier
                            .widthIn(max = 400.dp)
                            .fillMaxWidth()
                            .bubbleFluidity(targetScale = 0.97f, pullFactor = 0.05f)
                            .padding(horizontal = 16.dp, vertical = 8.dp)
                    ) {
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            modifier = Modifier.padding(vertical = 32.dp, horizontal = 16.dp)
                        ) {
                            // Radar Box (Static)
                            Box(
                                modifier = Modifier
                                    .padding(bottom = 24.dp)
                                    .size(96.dp)
                                    .background(MaterialTheme.colorScheme.surfaceVariant, CircleShape),
                                contentAlignment = Alignment.Center
                            ) {
                                Icon(
                                    imageVector = ImageVector.vectorResource(R.drawable.ic_qr_code_scanner),
                                    contentDescription = "Scan",
                                    modifier = Modifier.size(48.dp),
                                    tint = MaterialTheme.colorScheme.primary
                                )
                            }

                            Text(
                                text = "Scan to add Device",
                                fontSize = 22.sp,
                                fontWeight = FontWeight.Bold,
                                color = MaterialTheme.colorScheme.onBackground,
                                modifier = Modifier.padding(bottom = 4.dp)
                            )
                            Text(
                                text = "No Devices Connected. Make sure they are powered on and nearby.",
                                fontSize = 14.sp,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.padding(horizontal = 16.dp).padding(bottom = 24.dp),
                                textAlign = TextAlign.Center
                            )

                            DeXButton(
                                onClick = { launchQrScanner() },
                                modifier = Modifier.fillMaxWidth(0.8f).height(44.dp),
                                colors = ButtonDefaults.buttonColors(
                                    containerColor = MaterialTheme.colorScheme.primary,
                                    contentColor = MaterialTheme.colorScheme.onPrimary
                                )
                            ) {
                                Text(
                                    "Scan",
                                    fontWeight = FontWeight.Bold,
                                    fontSize = 14.sp
                                )
                            }

                            Spacer(modifier = Modifier.height(8.dp))

                            DeXTextButton(
                                onClick = { showTroubleshootDialog = true },
                                modifier = Modifier.fillMaxWidth().height(48.dp),
                                colors = ButtonDefaults.textButtonColors(
                                    contentColor = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            ) {
                                Text("Troubleshoot", fontSize = 14.sp, fontWeight = FontWeight.Medium)
                            }
                        }
                    }
                }

                androidx.compose.animation.AnimatedVisibility(
                    visible = devices.isNotEmpty(),
                    enter = com.example.dex.ui.theme.spatialMenuEnter(),
                    exit = com.example.dex.ui.theme.spatialMenuExit(),
                    modifier = Modifier.fillMaxSize()
                ) {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize().padding(horizontal = 16.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        items(devices, key = { it.info.fingerprint }) { device ->
                            val isTrusted = AuthState.pairedFingerprints.contains(device.info.fingerprint)
                            DeviceListItem(
                                modifier = Modifier.animateItem(),
                                device = device,
                                isTrusted = isTrusted,
                                onClick = {
                                    if (isTrusted) {
                                        selectedDevice = device
                                        filePickerLauncher.launch(arrayOf("*/*"))
                                    } else {
                                        if (pairingDeviceFingerprint == device.info.fingerprint) return@DeviceListItem
                                        pairingDeviceFingerprint = device.info.fingerprint
                                        Toast.makeText(context, context.getString(R.string.pairing_with, device.info.alias), Toast.LENGTH_SHORT).show()
                                        viewModel.sendHandshake(device) { success ->
                                            pairingDeviceFingerprint = null
                                            if (success) {
                                                Toast.makeText(context, context.getString(R.string.paired_successfully), Toast.LENGTH_SHORT).show()
                                            } else {
                                                Toast.makeText(context, context.getString(R.string.pairing_failed), Toast.LENGTH_SHORT).show()
                                            }
                                        }
                                    }
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



    if (showTrustedDevicesDialog) {
        TrustedDevicesDialog(
            onDismiss = { showTrustedDevicesDialog = false }
        )
    }

    if (showTroubleshootDialog) {
        AlertDialog(
            onDismissRequest = { showTroubleshootDialog = false },
            title = { Text(text = "Troubleshooting") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("1. Ensure both devices are powered on.")
                    Text("2. Check that both devices are connected to the same Wi-Fi network.")
                    Text("3. Try restarting the app on both devices.")
                }
            },
            confirmButton = {
                DeXTextButton(onClick = { showTroubleshootDialog = false }) {
                    Text("Close")
                }
            }
        )
    }
}


