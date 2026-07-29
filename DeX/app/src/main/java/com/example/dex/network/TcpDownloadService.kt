package com.example.dex.network

import java.io.File
import java.io.FileOutputStream
import java.net.InetSocketAddress
import java.nio.ByteBuffer
import java.nio.channels.SocketChannel
import kotlin.concurrent.thread

object TcpDownloadService {
    fun download(ip: String, port: Int, fileId: String, dest: File) {
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
                
                // Read from TCP and write directly to file
                val ioBuffer = ByteBuffer.allocateDirect(81920)
                while (socketChannel.read(ioBuffer) != -1) {
                    ioBuffer.flip()
                    while (ioBuffer.hasRemaining()) {
                        fileChannel.write(ioBuffer)
                    }
                    ioBuffer.clear()
                }
                
                fileChannel.close()
                socketChannel.close()
                println("TCP Download complete: ${dest.absolutePath}")
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }
}
