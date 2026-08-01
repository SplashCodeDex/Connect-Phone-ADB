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

class ShareTargetActivity : ComponentActivity() {

    private val sharedUris = mutableListOf<Uri>()

    @OptIn(ExperimentalMaterial3Api::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
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
            val device = DexAppContainer.discoveryEngine.devices.value[targetFingerprint]
            if (device != null) {
                pushToDevice(device)
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
                val discoveredDevices by DexAppContainer.discoveryEngine.devices.collectAsState()

                if (showSheet) {
                    ModalBottomSheet(
                        onDismissRequest = {
                            showSheet = false
                            finish()
                        },
                        sheetState = sheetState
                    ) {
                        ShareTargetScreen(
                            devices = discoveredDevices.values.toList(),
                            onSaveToSandbox = {
                                saveToSandbox()
                                showSheet = false
                            },
                            onSendToDevice = { device ->
                                pushToDevice(device)
                                showSheet = false
                            }
                        )
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
                    items(devices) { device ->
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

    private fun pushToDevice(device: DiscoveredDevice) {
        Toast.makeText(this, "Pushing to ${device.info.alias}...", Toast.LENGTH_SHORT).show()
        lifecycleScope.launch {
            withContext(Dispatchers.IO) {
                try {
                    val client = DexAppContainer.clientEngine
                    val filesMap = mutableMapOf<String, FileDto>()
                    val uriMap = mutableMapOf<String, Uri>()
                    
                    sharedUris.forEach { uri ->
                        val fileId = UUID.randomUUID().toString()
                        val fileName = getFileName(uri)
                        val fileSize = getFileSize(uri)
                        filesMap[fileId] = FileDto(
                            id = fileId,
                            fileName = fileName,
                            size = fileSize,
                            fileType = contentResolver.getType(uri) ?: "application/octet-stream"
                        )
                        uriMap[fileId] = uri
                    }

                    val req = PrepareUploadRequestDto(
                        info = RegisterDto(
                            alias = "DeX Android",
                            version = "2.0",
                            deviceModel = android.os.Build.MODEL,
                            deviceType = "mobile",
                            fingerprint = DexAppContainer.fingerprint,
                            port = 53317,
                            protocol = "https",
                            download = true,
                            identityHash = DexAppContainer.identityHash
                        ),
                        files = filesMap
                    )

                    val res = client.prepareUpload(device.ip, device.info.port, req)
                    if (res != null) {
                        var successCount = 0
                        res.files.forEach { (reqFileId, token) ->
                            val uri = uriMap[reqFileId]
                            val fileMeta = filesMap[reqFileId]
                            if (uri != null && fileMeta != null) {
                                contentResolver.openInputStream(uri)?.let { stream ->
                                    val success = client.uploadFile(
                                        ip = device.ip,
                                        port = device.info.port,
                                        sessionId = res.sessionId,
                                        fileId = reqFileId,
                                        token = token,
                                        stream = stream,
                                        fileSize = fileMeta.size
                                    )
                                    if (success) successCount++
                                }
                            }
                        }
                        
                        withContext(Dispatchers.Main) {
                            Toast.makeText(this@ShareTargetActivity, "Sent $successCount of ${sharedUris.size} files", Toast.LENGTH_LONG).show()
                        }
                    } else {
                        withContext(Dispatchers.Main) {
                            Toast.makeText(this@ShareTargetActivity, "Transfer rejected or failed", Toast.LENGTH_SHORT).show()
                        }
                    }
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
            finish()
        }
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
