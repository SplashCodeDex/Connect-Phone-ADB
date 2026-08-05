package com.example.dex.network

import android.content.Context
import android.content.pm.ServiceInfo
import android.net.Uri
import android.provider.OpenableColumns
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject
import java.util.UUID
import com.example.dex.R

class UploadWorker(
    appContext: Context,
    workerParams: WorkerParameters
) : CoroutineWorker(appContext, workerParams), KoinComponent {

    private val notificationId = 1001
    private val channelId = "upload_channel"

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val ip = inputData.getString("ip") ?: return@withContext Result.failure()
        val port = inputData.getInt("port", -1)
        if (port == -1) return@withContext Result.failure()
        val urisJson = inputData.getString("uris") ?: return@withContext Result.failure()

        val client by inject<ClientEngine>()
        val deviceConfig by inject<DeviceConfig>()

        val uriStrings = try {
            Json.decodeFromString<List<String>>(urisJson)
        } catch (e: Exception) {
            e.printStackTrace()
            return@withContext Result.failure()
        }
        val uris = uriStrings.map { Uri.parse(it) }

        // Initial foreground notification
        setForeground(createForegroundInfo(0, applicationContext.getString(R.string.upload_worker_preparing)))

        val fileData = uris.associate { uri ->
            try {
                applicationContext.contentResolver.takePersistableUriPermission(uri, android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } catch (e: SecurityException) { /* Ignored */ }
            
            var name = "shared_file"
            var size = 0L
            applicationContext.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    val sizeIdx = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (nameIdx >= 0) name = cursor.getString(nameIdx) ?: name
                    if (sizeIdx >= 0) size = cursor.getLong(sizeIdx)
                }
            }
            UUID.randomUUID().toString() to Triple(uri, name, size)
        }

        val totalBatchSize = fileData.values.sumOf { it.third }

        val prepareRequest = PrepareUploadRequestDto(
            info = RegisterDto(
                alias = getDeviceName(applicationContext), version = "2.0", deviceModel = android.os.Build.MODEL ?: "Android",
                deviceType = "mobile", fingerprint = deviceConfig.fingerprint,
                port = 53317, protocol = "https", download = true,
                identityHash = deviceConfig.identityHash
            ),
            files = fileData.mapValues { (id, d) -> 
                val partial = HashUtils.computePartialHash(applicationContext, d.first, d.third)
                FileDto(id, d.second, d.third, applicationContext.contentResolver.getType(d.first) ?: "application/octet-stream", partialHash = partial) 
            }
        )

        client.resetUploadState()

        val targetFingerprint = inputData.getString("targetFingerprint")
        val token = targetFingerprint?.let { AuthState.pairedTokens[it] }
        val response = client.prepareUpload(ip, port, prepareRequest, token)
        if (response != null) {
            
            var successCount = 0
            var previousBytes = 0L
            var index = 1

            fileData.forEach { (id, d) ->
                if (isStopped) return@withContext Result.failure()
                
                val token = response.files[id] ?: return@forEach
                if (token == "[SKIP]") {
                    successCount++
                } else {
                    applicationContext.contentResolver.openInputStream(d.first)?.use { stream ->
                        val success = client.uploadFile(
                            ip, port, response.sessionId, id, d.second, token, stream, d.third,
                            fileIndex = index, totalFiles = fileData.size, previousBatchBytes = previousBytes, totalBatchSize = totalBatchSize
                        ) { aggregateProgress ->
                            // The callback provides aggregate progress so we can update the notification
                            val progressInt = (aggregateProgress * 100).toInt()
                            setForeground(createForegroundInfo(progressInt, applicationContext.getString(R.string.upload_worker_progress, index, fileData.size, d.second)))
                        }
                        if (success) {
                            successCount++
                        }
                    }
                }
                previousBytes += d.third
                index++
            }
            client.finishUpload(successCount, fileData.size)
            if (successCount > 0) {
                return@withContext Result.success()
            } else {
                return@withContext Result.failure()
            }
        } else {
            return@withContext Result.failure()
        }
    }

    private fun createForegroundInfo(progress: Int, text: String): ForegroundInfo {
        val cancelIntent = androidx.work.WorkManager.getInstance(applicationContext).createCancelPendingIntent(id)

        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val channel = android.app.NotificationChannel(
                channelId,
                applicationContext.getString(R.string.upload_worker_channel),
                android.app.NotificationManager.IMPORTANCE_LOW
            )
            val manager = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
            manager.createNotificationChannel(channel)
        }

        val notification = NotificationCompat.Builder(applicationContext, channelId)
            .setContentTitle("Sending Files")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_upload) // Uses a system standard icon
            .setProgress(100, progress, false)
            .setOngoing(true)
            .addAction(android.R.drawable.ic_delete, "Cancel", cancelIntent)
            .build()

        return if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ForegroundInfo(notificationId, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            ForegroundInfo(notificationId, notification)
        }
    }
}
