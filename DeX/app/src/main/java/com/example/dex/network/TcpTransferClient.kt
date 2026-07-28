package com.example.dex.network

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Log
import java.io.InputStream
import java.net.Socket
import kotlin.concurrent.thread

object TcpTransferClient {
    private const val PORT = 53318

    /**
     * Streams an InputStream directly over TCP to the Windows PC.
     * Uses Little-Endian length prefix to match .NET BinaryReader.
     */
    fun sendStream(
        targetIp: String,
        filename: String,
        inputStream: InputStream,
        onComplete: () -> Unit,
        onError: (String) -> Unit
    ) {
        thread {
            try {
                Log.i("DeX", "Initiating TCP transfer to $targetIp...")
                val socket = Socket(targetIp, PORT)
                val outputStream = socket.getOutputStream()

                // 1. Build JSON Header
                val jsonHeader = """{"filename":"$filename"}"""
                val headerBytes = jsonHeader.toByteArray(Charsets.UTF_8)

                // 2. Write Int32 Length in LITTLE-ENDIAN
                // CRITICAL FIX: Java DataOutputStream writes Big-Endian. 
                // .NET BinaryReader expects Little-Endian. We must manually shift bytes.
                val length = headerBytes.size
                outputStream.write(length and 0xFF)
                outputStream.write((length shr 8) and 0xFF)
                outputStream.write((length shr 16) and 0xFF)
                outputStream.write((length shr 24) and 0xFF)

                // 3. Write JSON Header
                outputStream.write(headerBytes)

                // 4. Stream File Bytes (64KB chunks for max Wi-Fi throughput)
                val buffer = ByteArray(65536)
                var bytesRead: Int
                while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                    outputStream.write(buffer, 0, bytesRead)
                }

                // 5. Cleanup
                outputStream.flush()
                inputStream.close()
                socket.close()
                
                Log.i("DeX", "Transfer complete to $targetIp!")
                onComplete()

            } catch (e: Exception) {
                Log.e("DeX", "TCP Transfer failed", e)
                onError(e.message ?: "Unknown error")
            }
        }
    }

    /**
     * Helper to resolve modern Android Content Uris (e.g. from Photo Picker) into Streams.
     */
    fun sendUri(
        context: Context,
        targetIp: String,
        uri: Uri,
        onComplete: () -> Unit,
        onError: (String) -> Unit
    ) {
        var filename = "shared_file.dat"
        context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameIndex != -1) {
                    filename = cursor.getString(nameIndex)
                }
            }
        }
        
        val inputStream = context.contentResolver.openInputStream(uri)
        if (inputStream == null) {
            onError("Could not open stream for URI")
            return
        }
        
        sendStream(targetIp, filename, inputStream, onComplete, onError)
    }
}
