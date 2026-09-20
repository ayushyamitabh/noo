package dev.ayushya.noo

import java.io.File
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * Shared low-level WebDAV GET/PUT primitives (plain `HttpURLConnection`, no
 * new HTTP dependency) - used by [DownloadService], [ShareUploadService],
 * and [SyncEngine], which each independently re-implemented this same
 * ~20-line connect/stream/disconnect shape before this existed. Progress
 * reporting and cancellation are optional: the two foreground Services
 * pass both (user-visible, cancellable transfers); [SyncEngine]'s
 * background callers pass neither.
 *
 * Deliberately does *not* know about `OCS-APIRequest` - that header is for
 * OCS REST endpoints (shares/activity/quota), not plain WebDAV GET/PUT,
 * and was previously sent by mistake on some of these calls; dropped here
 * so every caller gets the same (correct) minimal header set.
 */
object DavTransfer {
    const val CONNECT_TIMEOUT_MS = 15000
    const val READ_TIMEOUT_MS = 30000
    const val UPLOAD_READ_TIMEOUT_MS = 60000
    private const val BUFFER_SIZE = 256 * 1024
    private const val PROGRESS_THROTTLE_MS = 200

    /** GETs [url] into [destination] (a plain file), creating parent dirs as needed. */
    fun get(
        url: URL,
        authHeader: String,
        destination: File,
        onProgress: ((received: Long, total: Long?) -> Unit)? = null,
        isCancelled: (() -> Boolean)? = null,
    ): Boolean {
        destination.parentFile?.mkdirs()
        return getInto(url, authHeader, { destination.outputStream() }, onProgress, isCancelled)
    }

    /**
     * GETs [url] into whatever [openOutput] returns - a plain `File` output
     * stream or, for [DownloadService]'s MediaStore-staged entries, a
     * `ContentResolver`-provided one the caller owns.
     */
    fun getInto(
        url: URL,
        authHeader: String,
        openOutput: () -> OutputStream?,
        onProgress: ((received: Long, total: Long?) -> Unit)? = null,
        isCancelled: (() -> Boolean)? = null,
    ): Boolean {
        val connection = url.openConnection() as HttpURLConnection
        return try {
            connection.requestMethod = "GET"
            connection.setRequestProperty("Authorization", authHeader)
            connection.connectTimeout = CONNECT_TIMEOUT_MS
            connection.readTimeout = READ_TIMEOUT_MS
            connection.connect()
            if (connection.responseCode !in 200..299) return false

            val total = connection.contentLengthLong.takeIf { it > 0 }
            val output = openOutput() ?: return false
            output.use { out ->
                connection.inputStream.use { input ->
                    copyWithProgress(input, out, total, onProgress, isCancelled)
                }
            }
            isCancelled?.invoke() != true
        } catch (e: Exception) {
            false
        } finally {
            connection.disconnect()
        }
    }

    /** PUTs [source]'s bytes to [url]. */
    fun put(
        url: URL,
        authHeader: String,
        source: File,
        contentType: String? = null,
        onProgress: ((sent: Long, total: Long) -> Unit)? = null,
        isCancelled: (() -> Boolean)? = null,
    ): Boolean {
        val length = source.length()
        val connection = url.openConnection() as HttpURLConnection
        return try {
            connection.requestMethod = "PUT"
            connection.doOutput = true
            connection.setFixedLengthStreamingMode(length)
            connection.setRequestProperty("Authorization", authHeader)
            if (contentType != null) connection.setRequestProperty("Content-Type", contentType)
            connection.connectTimeout = CONNECT_TIMEOUT_MS
            connection.readTimeout = UPLOAD_READ_TIMEOUT_MS

            connection.outputStream.use { output ->
                source.inputStream().use { input ->
                    copyWithProgress(input, output, length, { sent, total ->
                        onProgress?.invoke(sent, total ?: length)
                    }, isCancelled)
                }
            }
            if (isCancelled?.invoke() == true) {
                false
            } else {
                connection.responseCode in 200..299
            }
        } catch (e: Exception) {
            false
        } finally {
            connection.disconnect()
        }
    }

    private fun copyWithProgress(
        input: java.io.InputStream,
        output: OutputStream,
        total: Long?,
        onProgress: ((Long, Long?) -> Unit)?,
        isCancelled: (() -> Boolean)?,
    ) {
        val buffer = ByteArray(BUFFER_SIZE)
        var transferred = 0L
        var lastEmit = 0L
        while (isCancelled?.invoke() != true) {
            val read = input.read(buffer)
            if (read == -1) break
            output.write(buffer, 0, read)
            transferred += read
            if (onProgress != null) {
                val now = System.currentTimeMillis()
                if (now - lastEmit >= PROGRESS_THROTTLE_MS) {
                    lastEmit = now
                    onProgress(transferred, total)
                }
            }
        }
    }
}
