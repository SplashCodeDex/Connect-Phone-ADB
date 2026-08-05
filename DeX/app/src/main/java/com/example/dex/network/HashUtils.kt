package com.example.dex.network

import android.content.Context
import android.net.Uri
import java.security.MessageDigest
import kotlin.math.min

object HashUtils {
    private const val PARTIAL_SIZE = 32768 // 32KB

    fun computePartialHash(context: Context, uri: Uri, fileSize: Long): String? {
        if (fileSize == 0L) return null
        return try {
            val md = MessageDigest.getInstance("SHA-256")
            val buffer = ByteArray(PARTIAL_SIZE)

            context.contentResolver.openInputStream(uri)?.use { stream ->
                // Hash first 32KB
                val bytesReadHead = stream.read(buffer, 0, PARTIAL_SIZE)
                if (bytesReadHead > 0) {
                    md.update(buffer, 0, bytesReadHead)
                }

                // If file is large enough, skip to the last 32KB and hash it
                if (fileSize > PARTIAL_SIZE * 2) {
                    val bytesToSkip = fileSize - bytesReadHead - PARTIAL_SIZE
                    var skipped = 0L
                    while (skipped < bytesToSkip) {
                        val s = stream.skip(bytesToSkip - skipped)
                        if (s <= 0) {
                            // Fallback if skip() fails to advance (e.g. some custom InputStreams)
                            val readBytes = stream.read(buffer, 0, min(buffer.size.toLong(), bytesToSkip - skipped).toInt())
                            if (readBytes == -1) break
                            skipped += readBytes
                        } else {
                            skipped += s
                        }
                    }
                    val bytesReadTail = stream.read(buffer, 0, PARTIAL_SIZE)
                    if (bytesReadTail > 0) {
                        md.update(buffer, 0, bytesReadTail)
                    }
                } else if (fileSize > bytesReadHead) {
                    // File is between 32KB and 64KB, just read the rest
                    var remaining = fileSize - bytesReadHead
                    while (remaining > 0) {
                        val read = stream.read(buffer, 0, min(remaining, PARTIAL_SIZE.toLong()).toInt())
                        if (read == -1) break
                        md.update(buffer, 0, read)
                        remaining -= read
                    }
                }
            }
            
            md.digest().joinToString("") { "%02X".format(it) }
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }
}
