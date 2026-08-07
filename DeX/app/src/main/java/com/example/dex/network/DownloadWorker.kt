package com.example.dex.network

import android.content.Context
import android.content.pm.ServiceInfo
import android.net.Uri
import androidx.core.net.toUri
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.InetSocketAddress
import java.nio.ByteBuffer
import java.nio.channels.SocketChannel

class DownloadWorker(
    private val context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {

    private val notificationId = 1002
    private val channelId = "download_channel"

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val ip = inputData.getString("ip") ?: return@withContext Result.failure()
        val port = inputData.getInt("port", -1)
        val fileId = inputData.getString("fileId") ?: return@withContext Result.failure()
        val fileName = inputData.getString("fileName") ?: "downloaded_file"
        val fileSize = inputData.getLong("fileSize", 100L)
        val destDirUri = inputData.getString("destDirUri") ?: return@withContext Result.failure()

        if (port == -1) return@withContext Result.failure()

        TcpDownloadService.updateState(DownloadState(fileName = fileName, isDownloading = true))
        setForeground(createForegroundInfo(0, "Preparing download..."))

        try {
            val socketChannel = SocketChannel.open(InetSocketAddress(ip, port))
            val fileIdBytes = fileId.toByteArray(Charsets.UTF_8)
            val buffer = ByteBuffer.wrap(fileIdBytes)
            while (buffer.hasRemaining()) {
                if (isStopped) {
                    socketChannel.close()
                    TcpDownloadService.updateState(DownloadState(fileName = fileName, error = "Download cancelled", isDownloading = false))
                    return@withContext Result.failure()
                }
                socketChannel.write(buffer)
            }

            val out = SafStorage.openOutputStream(context, destDirUri.toUri(), fileName)
            if (out == null) {
                socketChannel.close()
                TcpDownloadService.updateState(DownloadState(fileName = fileName, error = "Cannot write to Downloads/DeX", isDownloading = false))
                return@withContext Result.failure()
            }

            var downloaded = 0L
            val ioBuffer = ByteBuffer.allocateDirect(81920)
            
            var lastUpdateMillis = System.currentTimeMillis()

            while (socketChannel.read(ioBuffer) != -1) {
                if (isStopped) {
                    out.close()
                    socketChannel.close()
                    TcpDownloadService.updateState(DownloadState(fileName = fileName, error = "Download cancelled", isDownloading = false))
                    return@withContext Result.failure()
                }

                ioBuffer.flip()
                downloaded += ioBuffer.remaining()

                val bytes = ByteArray(ioBuffer.remaining())
                ioBuffer.get(bytes)
                out.write(bytes)
                ioBuffer.clear()

                val now = System.currentTimeMillis()
                // Update UI and Notification every ~200ms so we don't spam the OS
                if (now - lastUpdateMillis > 200) {
                    val progress = if (fileSize > 0) downloaded.toFloat() / fileSize else 0f
                    TcpDownloadService.updateState(
                        DownloadState(
                            fileName = fileName,
                            progress = progress,
                            isDownloading = true
                        )
                    )
                    setForeground(createForegroundInfo((progress * 100).toInt(), "Downloading: $fileName"))
                    lastUpdateMillis = now
                }
            }

            out.close()
            socketChannel.close()
            println("TCP Download complete: $fileName")
            
            TcpDownloadService.updateState(DownloadState(fileName = fileName, progress = 1f, isSuccess = true))
            
            // Send completion notification
            val successNotification = NotificationCompat.Builder(context, channelId)
                .setContentTitle("File Received")
                .setContentText("Saved to Downloads/DeX/$fileName")
                .setSmallIcon(android.R.drawable.stat_sys_download_done)
                .setAutoCancel(true)
                .build()
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
            nm.notify(fileName.hashCode(), successNotification)

            Result.success()
        } catch (e: Exception) {
            e.printStackTrace()
            TcpDownloadService.updateState(DownloadState(fileName = fileName, error = e.message, isDownloading = false))
            Result.failure()
        }
    }

    private fun createForegroundInfo(progress: Int, text: String): ForegroundInfo {
        val cancelIntent = androidx.work.WorkManager.getInstance(applicationContext).createCancelPendingIntent(id)

        val notification = NotificationCompat.Builder(applicationContext, channelId)
            .setContentTitle("Receiving File")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_download)
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