package dev.ayushya.noo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.IBinder
import android.provider.MediaStore
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import org.json.JSONArray
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Foreground service that downloads one or more files over WebDAV straight
 * into the device's public Downloads folder, independent of MainActivity/
 * the Flutter engine being alive - the download counterpart of
 * ShareUploadService.kt (see its doc comment for the full rationale: only
 * a real Android Service survives the app being closed mid-transfer, the
 * same guarantee a real file-manager app's download notification gives
 * you). Re-implements a plain WebDAV GET here in Kotlin for the same
 * reason uploads do - keep NextcloudService.downloadToFile in sync if
 * download semantics change.
 *
 * Started via the `dev.ayushya.noo/download_service` MethodChannel
 * (MainActivity.kt). Shows one persistent, cancellable notification for
 * the whole batch, same UX as ShareUploadService's.
 */
class DownloadService : Service() {
    companion object {
        const val ACTION_CANCEL = "dev.ayushya.noo.action.CANCEL_DOWNLOAD"
        const val EXTRA_FILES = "files" // JSON array of {path, name, mimeType, size}
        const val EXTRA_SERVER_URL = "serverUrl"
        const val EXTRA_USERNAME = "username"
        const val EXTRA_AUTH_HEADER = "authHeader"

        private const val CHANNEL_ID = "file_downloads"
        private const val NOTIFICATION_ID = 4301
    }

    private val cancelled = AtomicBoolean(false)
    private var downloadThread: Thread? = null

    private data class DownloadFile(
        val path: String,
        val name: String,
        val mimeType: String?,
        val size: Long?,
    )

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_CANCEL) {
            cancelled.set(true)
            return START_NOT_STICKY
        }

        val filesJson = intent?.getStringExtra(EXTRA_FILES)
        val serverUrl = intent?.getStringExtra(EXTRA_SERVER_URL)
        val username = intent?.getStringExtra(EXTRA_USERNAME)
        val authHeader = intent?.getStringExtra(EXTRA_AUTH_HEADER)
        if (filesJson == null || serverUrl == null || username == null || authHeader == null) {
            stopSelf()
            return START_NOT_STICKY
        }

        createNotificationChannel()
        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            buildProgressNotification("Preparing to download…", null, indeterminate = true),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            } else {
                0
            },
        )

        // A second batch arriving mid-download is dropped rather than
        // queued - same tradeoff ShareUploadService makes, rare in
        // practice and not worth a real queue for.
        if (downloadThread == null) {
            val files = parseFiles(filesJson)
            downloadThread = Thread {
                runDownloads(files, serverUrl, username, authHeader)
            }.also { it.start() }
        }

        return START_NOT_STICKY
    }

    private fun parseFiles(json: String): List<DownloadFile> {
        val arr = JSONArray(json)
        return (0 until arr.length()).map { i ->
            val obj = arr.getJSONObject(i)
            DownloadFile(
                path = obj.getString("path"),
                name = obj.getString("name"),
                mimeType = if (obj.isNull("mimeType")) null else obj.getString("mimeType"),
                size = if (obj.isNull("size")) null else obj.getLong("size"),
            )
        }
    }

    private fun runDownloads(
        files: List<DownloadFile>,
        serverUrl: String,
        username: String,
        authHeader: String,
    ) {
        var succeeded = 0
        var failed = 0
        val cleanServer = serverUrl.trimEnd('/')

        for ((index, file) in files.withIndex()) {
            if (cancelled.get()) break
            val label = if (files.size == 1) file.name else "${file.name} (${index + 1}/${files.size})"
            try {
                var cleanPath = file.path.trim()
                if (!cleanPath.startsWith("/")) cleanPath = "/$cleanPath"
                val encodedPath = cleanPath.split("/").joinToString("/") { Uri.encode(it) }
                val url = URL("$cleanServer/remote.php/dav/files/$username$encodedPath")
                val ok = downloadFile(file, url, authHeader) { received, total ->
                    notify(
                        buildProgressNotification(
                            "Downloading $label…",
                            progressFraction(received, total),
                            indeterminate = total == null,
                        ),
                    )
                }
                if (ok) succeeded++ else failed++
            } catch (e: Exception) {
                failed++
            }
        }

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val finalText = when {
            cancelled.get() -> "Download cancelled"
            failed == 0 && files.size == 1 -> "Downloaded ${files.first().name}"
            failed == 0 -> "Downloaded $succeeded of ${files.size} files"
            else -> "Downloaded $succeeded of ${files.size} files - $failed failed"
        }
        manager.notify(NOTIFICATION_ID, buildFinalNotification(finalText))

        stopForeground(STOP_FOREGROUND_DETACH)
        stopSelf()
    }

    private fun progressFraction(received: Long, total: Long?): Float? {
        if (total == null || total <= 0) return null
        return (received.toFloat() / total.toFloat()).coerceIn(0f, 1f)
    }

    /// Streams the GET response straight into the public Downloads
    /// collection via MediaStore (API 29+) - scoped storage means a
    /// background Service can't prompt a SAF picker the way `file_saver`
    /// does from the Flutter/Activity side, so this writes directly to the
    /// Downloads collection instead, same place a browser download lands.
    /// Pre-Q devices fall back to the legacy public Downloads directory.
    private fun downloadFile(
        file: DownloadFile,
        url: URL,
        authHeader: String,
        onProgress: (Long, Long?) -> Unit,
    ): Boolean {
        val connection = url.openConnection() as HttpURLConnection
        return try {
            connection.requestMethod = "GET"
            connection.setRequestProperty("Authorization", authHeader)
            connection.setRequestProperty("OCS-APIRequest", "true")
            connection.connectTimeout = 15000
            connection.readTimeout = 30000
            connection.connect()

            if (connection.responseCode !in 200..299) return false

            val total = file.size ?: connection.contentLengthLong.takeIf { it > 0 }
            val mimeType = file.mimeType ?: "application/octet-stream"
            val outputUri = createDownloadsEntry(file.name, mimeType) ?: return false

            val stream = contentResolver.openOutputStream(outputUri) ?: return false
            stream.use { output ->
                connection.inputStream.use { input ->
                    val buffer = ByteArray(256 * 1024)
                    var received = 0L
                    var lastEmit = 0L
                    while (!cancelled.get()) {
                        val read = input.read(buffer)
                        if (read == -1) break
                        output.write(buffer, 0, read)
                        received += read
                        val now = System.currentTimeMillis()
                        if (now - lastEmit >= 200) {
                            lastEmit = now
                            onProgress(received, total)
                        }
                    }
                }
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }
                contentResolver.update(outputUri, values, null, null)
            }

            if (cancelled.get()) {
                contentResolver.delete(outputUri, null, null)
                false
            } else {
                true
            }
        } catch (e: Exception) {
            false
        } finally {
            connection.disconnect()
        }
    }

    private fun createDownloadsEntry(name: String, mimeType: String): Uri? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, mimeType)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
        } else {
            @Suppress("DEPRECATION")
            val downloadsDir =
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            if (!downloadsDir.exists()) downloadsDir.mkdirs()
            Uri.fromFile(File(downloadsDir, name))
        }
    }

    private fun notify(notification: Notification) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, notification)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "File downloads",
                NotificationManager.IMPORTANCE_LOW,
            ).apply { description = "Progress for files downloaded from Noo" }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildProgressNotification(
        text: String,
        progress: Float?,
        indeterminate: Boolean,
    ): Notification {
        val cancelIntent = Intent(this, DownloadService::class.java).apply { action = ACTION_CANCEL }
        val cancelPendingIntent = PendingIntent.getService(
            this,
            0,
            cancelIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle("Downloading from Noo")
            .setContentText(text)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Cancel", cancelPendingIntent)
        when {
            indeterminate -> builder.setProgress(100, 0, true)
            progress != null -> builder.setProgress(100, (progress * 100).toInt(), false)
        }
        return builder.build()
    }

    private fun buildFinalNotification(text: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle("Noo")
            .setContentText(text)
            .setOngoing(false)
            .setAutoCancel(true)
            .build()
    }

    override fun onDestroy() {
        cancelled.set(true)
        super.onDestroy()
    }
}
