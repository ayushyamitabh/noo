package dev.ayushya.noo

import android.app.Notification
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
import java.net.URL

/**
 * Foreground service that downloads one or more files over WebDAV straight
 * into the device's public Downloads folder, independent of MainActivity/
 * the Flutter engine being alive - the download counterpart of
 * ShareUploadService.kt (see its doc comment: only a real Android Service
 * survives the app being closed mid-transfer, the same guarantee a real
 * file-manager app's download notification gives you). GET itself is
 * [DavTransfer.getInto]; this file owns only what's specific to
 * downloading - MediaStore staging and the notification/queue plumbing.
 *
 * Started via the `dev.ayushya.noo/download_service` MethodChannel
 * (MainActivity.kt). Shows one persistent, cancellable notification for
 * the whole batch; a second batch arriving mid-download queues behind the
 * first (see [TransferQueue]) instead of being dropped.
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

    private data class DownloadFile(
        val path: String,
        val name: String,
        val mimeType: String?,
        val size: Long?,
    )

    private data class DownloadBatch(
        val files: List<DownloadFile>,
        val serverUrl: String,
        val username: String,
        val authHeader: String,
    )

    @Volatile
    private var cancelled = false
    private val queue = TransferQueue<DownloadBatch> { runDownloads(it) }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_CANCEL) {
            cancelled = true
            queue.clearPending()
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

        NooNotificationChannels.ensure(
            this,
            CHANNEL_ID,
            "File downloads",
            NotificationManager.IMPORTANCE_LOW,
            "Progress for files downloaded from Noo",
        )
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

        queue.enqueue(DownloadBatch(parseFiles(filesJson), serverUrl, username, authHeader))
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

    private fun runDownloads(batch: DownloadBatch) {
        cancelled = false
        var succeeded = 0
        var failed = 0
        val cleanServer = batch.serverUrl.trimEnd('/')

        for ((index, file) in batch.files.withIndex()) {
            if (cancelled) break
            val label = if (batch.files.size == 1) {
                file.name
            } else {
                "${file.name} (${index + 1}/${batch.files.size})"
            }
            try {
                var cleanPath = file.path.trim()
                if (!cleanPath.startsWith("/")) cleanPath = "/$cleanPath"
                val encodedPath = cleanPath.split("/").joinToString("/") { Uri.encode(it) }
                val url = URL("$cleanServer/remote.php/dav/files/${batch.username}$encodedPath")
                val ok = downloadFile(file, url, batch.authHeader) { received, total ->
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

        val finalText = when {
            cancelled -> "Download cancelled"
            failed == 0 && batch.files.size == 1 -> "Downloaded ${batch.files.first().name}"
            failed == 0 -> "Downloaded $succeeded of ${batch.files.size} files"
            else -> "Downloaded $succeeded of ${batch.files.size} files - $failed failed"
        }
        manager().notify(NOTIFICATION_ID, buildFinalNotification(finalText))

        if (queue.pendingCount == 0) {
            stopForeground(STOP_FOREGROUND_DETACH)
            stopSelf()
        }
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
        val mimeType = file.mimeType ?: "application/octet-stream"
        var outputUri: Uri? = null
        val ok = DavTransfer.getInto(
            url,
            authHeader,
            openOutput = {
                val uri = createDownloadsEntry(file.name, mimeType)
                if (uri != null) {
                    outputUri = uri
                    contentResolver.openOutputStream(uri)
                } else {
                    null
                }
            },
            onProgress = { received, total -> onProgress(received, file.size ?: total) },
            isCancelled = { cancelled },
        )

        outputUri?.let { uri ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }
                contentResolver.update(uri, values, null, null)
            }
            if (!ok) contentResolver.delete(uri, null, null)
        }
        return ok
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

    private fun manager() =
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun notify(notification: Notification) {
        manager().notify(NOTIFICATION_ID, notification)
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
        cancelled = true
        super.onDestroy()
    }
}
