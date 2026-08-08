package com.example.dex.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.dex.R
import com.example.dex.network.DownloadState
import com.example.dex.network.UploadState

@Composable
fun TransferProgressOverlay(
    downloadState: DownloadState,
    uploadState: UploadState,
    onCancelDownload: () -> Unit,
    onCancelUpload: () -> Unit
) {
    val isVisible = downloadState.isDownloading || downloadState.isSuccess || uploadState.isUploading || uploadState.isSuccess

    AnimatedVisibility(
        visible = isVisible,
        enter = expandVertically(expandFrom = Alignment.Top),
        exit = shrinkVertically(shrinkTowards = Alignment.Top)
    ) {
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
                        Text(stringResource(R.string.downloading), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                        DeXTextButton(onClick = onCancelDownload) {
                            Text(stringResource(R.string.cancel), color = MaterialTheme.colorScheme.error)
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
                    stringResource(R.string.download_success, downloadState.fileName), 
                    modifier = Modifier.padding(16.dp), 
                    fontWeight = FontWeight.Bold
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
                        Text(pluralStringResource(R.plurals.uploading_progress, uploadState.totalFiles, uploadState.currentFileIndex, uploadState.totalFiles), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                        DeXTextButton(onClick = onCancelUpload) {
                            Text(stringResource(R.string.cancel), color = MaterialTheme.colorScheme.error)
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
                    Text(stringResource(R.string.toast_percent_total, (uploadState.aggregateProgress * 100).toInt()), style = MaterialTheme.typography.bodySmall)
                }
            }
        } else if (uploadState.isSuccess) {
            Surface(
                color = MaterialTheme.colorScheme.primaryContainer,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(
                    stringResource(R.string.upload_success, uploadState.fileName), 
                    modifier = Modifier.padding(16.dp), 
                    fontWeight = FontWeight.Bold
                )
            }
        }
    }
}
