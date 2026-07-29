package com.example.dex.network

import java.io.File
import java.io.FileOutputStream
import java.net.InetSocketAddress
import java.nio.ByteBuffer
import java.nio.channels.SocketChannel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlin.concurrent.thread

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

    fun download(ip: String, port: Int, fileId: String, fileName: String, fileSize: Long, dest: File) {
        _downloadState.value = DownloadState(fileName = fileName, isDownloading = true)
        
        thread(start = true) {
            try {
                val socketChannel = SocketChannel.open(InetSocketAddress(ip, port))
                // Send fileId
                val fileIdBytes = fileId.toByteArray(Charsets.UTF_8)
                val buffer = ByteBuffer.wrap(fileIdBytes)
                while (buffer.hasRemaining()) {
                    socketChannel.write(buffer)
                }
                
                dest.parentFile?.mkdirs()
                val fileChannel = FileOutputStream(dest).channel
                
                var downloaded = 0L
                val ioBuffer = ByteBuffer.allocateDirect(81920)
                while (socketChannel.read(ioBuffer) != -1) {
                    ioBuffer.flip()
                    downloaded += ioBuffer.remaining()
                    
                    while (ioBuffer.hasRemaining()) {
                        fileChannel.write(ioBuffer)
                    }
                    ioBuffer.clear()
                    
                    _downloadState.value = DownloadState(
                        fileName = fileName,
                        progress = downloaded.toFloat() / fileSize,
                        isDownloading = true
                    )
                }
                
                fileChannel.close()
                socketChannel.close()
                println("TCP Download complete: ${dest.absolutePath}")
                _downloadState.value = DownloadState(fileName = fileName, progress = 1f, isSuccess = true)
            } catch (e: Exception) {
                e.printStackTrace()
                _downloadState.value = DownloadState(fileName = fileName, error = e.message)
            }
        }
    }
}
