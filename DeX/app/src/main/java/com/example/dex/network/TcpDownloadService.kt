package com.example.dex.network

import android.content.Context
import android.net.Uri
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import java.util.UUID
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

data class DownloadState(
    val fileName: String = "",
    val progress: Float = 0f,
    val isDownloading: Boolean = false,
    val isSuccess: Boolean = false,
    val error: String? = null
)

object TcpDownloadService {
    private val _downloadState = MutableStateFlow(DownloadState())
    val downloadState = _downloadState.asStateFlow()

    fun resetDownloadState() {
        _downloadState.value = DownloadState()
    }

    var activeWorkId: UUID? = null

    fun updateState(state: DownloadState) {
        _downloadState.value = state
    }

    fun download(context: Context, ip: String, port: Int, fileId: String, fileName: String, fileSize: Long, destDirUri: Uri) {
        _downloadState.value = DownloadState(fileName = fileName, isDownloading = true)
        
        val inputData = Data.Builder()
            .putString("ip", ip)
            .putInt("port", port)
            .putString("fileId", fileId)
            .putString("fileName", fileName)
            .putLong("fileSize", fileSize)
            .putString("destDirUri", destDirUri.toString())
            .build()

        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()

        val downloadWorkRequest = OneTimeWorkRequestBuilder<DownloadWorker>()
            .setConstraints(constraints)
            .setInputData(inputData)
            .build()

        activeWorkId = downloadWorkRequest.id
        WorkManager.getInstance(context).enqueue(downloadWorkRequest)
    }

    fun cancelDownload(context: Context) {
        activeWorkId?.let {
            WorkManager.getInstance(context).cancelWorkById(it)
        }
        _downloadState.update { it.copy(isDownloading = false, error = "Cancelled by user") }
    }
}
