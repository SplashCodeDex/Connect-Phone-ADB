package com.example.dex

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Environment
import android.provider.OpenableColumns
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.Computer
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Smartphone
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.lifecycleScope
import com.example.dex.network.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import androidx.activity.result.contract.ActivityResultContracts
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import androidx.work.workDataOf
import kotlinx.serialization.json.Json
import kotlinx.serialization.encodeToString
import androidx.work.Data
import com.example.dex.network.DiscoveryEngine
import com.example.dex.network.ClientEngine
import org.koin.android.ext.android.inject

class ShareTargetActivity : ComponentActivity() {

    private val sharedUris = mutableListOf<Uri>()
    private val discoveryEngine: DiscoveryEngine by inject()
    private val clientEngine: ClientEngine by inject()

    @OptIn(ExperimentalMaterial3Api::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        val notificationPermissionLauncher = registerForActivityResult(
            ActivityResultContracts.RequestPermission()
        ) { _ -> }
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            notificationPermissionLauncher.launch(android.Manifest.permission.POST_NOTIFICATIONS)
        }
        
        // Handle incoming intent
        when (intent?.action) {
            Intent.ACTION_SEND -> {
                (intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))?.let { sharedUris.add(it) }
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.let { sharedUris.addAll(it) }
            }
        }

        if (sharedUris.isEmpty()) {
            Toast.makeText(this, "No files to share", Toast.LENGTH_SHORT).show()
            finish()
            return
        }

        val targetFingerprint = intent?.getStringExtra("EXTRA_TARGET_FINGERPRINT")
        if (targetFingerprint != null) {
            val device = discoveryEngine.devices.value[targetFingerprint]
            if (device != null) {
                sendUrisToDevice(device, sharedUris)
            } else {
                Toast.makeText(this, "PC offline. Saved to Sandbox instead.", Toast.LENGTH_LONG).show()
                saveToSandbox()
            }
            return
        }

        setContent {
            MaterialTheme {
                val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
                var showSheet by remember { mutableStateOf(true) }
                val discoveredDevices by discoveryEngine.devices.collectAsState()
                val uploadState by clientEngine.uploadState.collectAsState()

                if (showSheet) {
                    ModalBottomSheet(
                        onDismissRequest = {
                            showSheet = false
                            finish()
                        },
                        sheetState = sheetState
                    ) {
                        if (uploadState.isUploading || uploadState.isSuccess || uploadState.error != null) {
                            UploadProgressScreen(uploadState)
                        } else {
                            ShareTargetScreen(
                                devices = discoveredDevices.values.toList(),
                                onSaveToSandbox = {
                                    saveToSandbox()
                                    showSheet = false
                                },
                                onSendToDevice = { device ->
                                    sendUrisToDevice(device, sharedUris)
                                    clientEngine.resetUploadState()
                                    startActivity(Intent(this@ShareTargetActivity, MainActivity::class.java))
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    @Composable
    fun ShareTargetScreen(
        devices: List<DiscoveredDevice>,
        onSaveToSandbox: () -> Unit,
        onSendToDevice: (DiscoveredDevice) -> Unit
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 32.dp, start = 16.dp, end = 16.dp)
        ) {
            Text(
                text = "Send ${sharedUris.size} file(s) to...",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(bottom = 16.dp)
            )

            // WAN Dummies
            Text("WAN Devices (Coming Soon)", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(modifier = Modifier.height(8.dp))
            LazyRow(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                items(2) { index ->
                    DeviceItem(
                        name = "Remote User ${index + 1}",
                        icon = Icons.Default.Cloud,
                        isDummy = true,
                        onClick = {}
                    )
                }
            }
            
            Spacer(modifier = Modifier.height(24.dp))
            HorizontalDivider()
            Spacer(modifier = Modifier.height(16.dp))

            // LAN Devices
            Text("LAN Devices", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(modifier = Modifier.height(8.dp))
            
            if (devices.isEmpty()) {
                Text(
                    text = "No local devices found.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(vertical = 16.dp)
                )
            } else {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    items(devices, key = { it.info.fingerprint }) { device ->
                        DeviceItem(
                            name = device.info.alias,
                            icon = if (device.info.deviceType == "desktop") Icons.Default.Computer else Icons.Default.Smartphone,
                            isDummy = false,
                            onClick = { onSendToDevice(device) }
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(24.dp))

            // Sandbox
            Button(
                onClick = onSaveToSandbox,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.secondaryContainer, contentColor = MaterialTheme.colorScheme.onSecondaryContainer)
            ) {
                Icon(Icons.Default.Folder, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("Save to Local DeX Sandbox")
            }
        }
    }

    @Composable
    fun DeviceItem(name: String, icon: ImageVector, isDummy: Boolean, onClick: () -> Unit) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier
                .width(80.dp)
                .clip(RoundedCornerShape(8.dp))
                .clickable(enabled = !isDummy, onClick = onClick)
                .padding(4.dp)
        ) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .size(56.dp)
                    .background(
                        if (isDummy) MaterialTheme.colorScheme.surfaceVariant else MaterialTheme.colorScheme.primaryContainer,
                        CircleShape
                    )
            ) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = if (isDummy) MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f) else MaterialTheme.colorScheme.onPrimaryContainer
                )
            }
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = name,
                style = MaterialTheme.typography.bodySmall,
                textAlign = TextAlign.Center,
                maxLines = 2,
                color = if (isDummy) MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f) else MaterialTheme.colorScheme.onSurface
            )
        }
    }

    @Composable
    fun UploadProgressScreen(uploadState: UploadState) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 32.dp, start = 16.dp, end = 16.dp)
        ) {
            if (uploadState.isUploading) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("Uploading ${uploadState.currentFileIndex} of ${uploadState.totalFiles} files...", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                    TextButton(onClick = { clientEngine.cancelUpload(this@ShareTargetActivity) }) {
                        Text("Cancel", color = MaterialTheme.colorScheme.error)
                    }
                }
                Spacer(modifier = Modifier.height(4.dp))
                Text(uploadState.fileName, style = MaterialTheme.typography.bodySmall, maxLines = 1)
                Spacer(modifier = Modifier.height(16.dp))
                LinearProgressIndicator(
                    progress = { uploadState.aggregateProgress },
                    modifier = Modifier.fillMaxWidth(),
                    color = MaterialTheme.colorScheme.primary,
                    trackColor = MaterialTheme.colorScheme.surfaceVariant
                )
                Spacer(modifier = Modifier.height(8.dp))
                Text("${(uploadState.aggregateProgress * 100).toInt()}% Total", style = MaterialTheme.typography.bodySmall, modifier = Modifier.align(Alignment.End))
            } else if (uploadState.isSuccess) {
                Text(
                    "Successfully Uploaded ${uploadState.fileName}", 
                    style = MaterialTheme.typography.bodyLarge, 
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.primary
                )
            } else if (uploadState.error != null) {
                Text(
                    "Upload Failed: ${uploadState.error}", 
                    style = MaterialTheme.typography.bodyLarge, 
                    color = MaterialTheme.colorScheme.error
                )
            }
        }
    }

    private fun saveToSandbox() {
        lifecycleScope.launch {
            withContext(Dispatchers.IO) {
                try {
                    val sandboxDir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "DeX")
                    if (!sandboxDir.exists()) {
                        sandboxDir.mkdirs()
                    }

                    sharedUris.forEach { uri ->
                        val fileName = getFileName(uri)
                        val destFile = File(sandboxDir, fileName)
                        
                        // Handle collision
                        var finalFile = destFile
                        var counter = 1
                        while (finalFile.exists()) {
                            val nameWithoutExt = fileName.substringBeforeLast(".")
                            val ext = if (fileName.contains(".")) "." + fileName.substringAfterLast(".") else ""
                            finalFile = File(sandboxDir, "$nameWithoutExt ($counter)$ext")
                            counter++
                        }

                        contentResolver.openInputStream(uri)?.use { input ->
                            FileOutputStream(finalFile).use { output ->
                                input.copyTo(output)
                            }
                        }
                    }
                    withContext(Dispatchers.Main) {
                        Toast.makeText(this@ShareTargetActivity, "Saved to DeX Sandbox", Toast.LENGTH_SHORT).show()
                    }
                } catch (e: Exception) {
                    e.printStackTrace()
                    withContext(Dispatchers.Main) {
                        Toast.makeText(this@ShareTargetActivity, "Failed to save files", Toast.LENGTH_SHORT).show()
                    }
                }
            }
            finish()
        }
    }

    private fun sendUrisToDevice(device: com.example.dex.network.DiscoveredDevice, uris: List<Uri>) {
        clientEngine.resetUploadState()
        
        val urisJson = try {
            Json.encodeToString(sharedUris.map { it.toString() })
        } catch (e: Exception) {
            e.printStackTrace()
            return
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
            
        clientEngine.activeWorkId = workRequest.id
        WorkManager.getInstance(this).enqueue(workRequest)
    }

    private fun getFileName(uri: Uri): String {
        var result: String? = null
        if (uri.scheme == "content") {
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0) {
                        result = cursor.getString(index)
                    }
                }
            }
        }
        if (result == null) {
            result = uri.path
            val cut = result?.lastIndexOf('/') ?: -1
            if (cut != -1) {
                result = result?.substring(cut + 1)
            }
        }
        return result ?: "SharedFile_${System.currentTimeMillis()}"
    }
    
    private fun getFileSize(uri: Uri): Long {
        var result: Long = 0
        if (uri.scheme == "content") {
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (index >= 0) {
                        result = cursor.getLong(index)
                    }
                }
            }
        }
        return result
    }
}
