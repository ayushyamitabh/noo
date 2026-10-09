package dev.ayushya.noo

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import org.json.JSONArray
import java.io.File
import java.io.FileOutputStream
import java.net.URL

/**
 * Foreground service that prepares (copies from a content:// Uri) and
 * uploads one or more "Share to Noo" files over WebDAV, independent of
 * MainActivity/the Flutter engine being alive - the whole point is that
 * closing the app right after confirming a destination in ShareUploadView
 * doesn't interrupt the upload, the same way a file-manager app's own
 * upload notification survives the app being closed.
 *
 * PUT itself is [DavTransfer.put]; this file owns only what's specific to
 * a share-upload - materializing the source content:// Uri into a real
 * file first (WebDAV PUT needs a known Content-Length, which streaming
 * straight from a content:// Uri can't always provide) and the
 * notification/queue plumbing.
 *
 * Started via the `dev.ayushya.noo/upload_service` MethodChannel
 * (MainActivity.kt) with credentials/destination passed as Intent extras -
 * never has an Activity in the loop after that. Shows one persistent,
 * cancellable notification for the whole batch; a second share arriving
 * mid-upload queues behind the first (see [TransferQueue]) instead of
 * being dropped.
 */
class ShareUploadService : Service() {
    companion object {
        const val ACTION_CANCEL = "dev.ayushya.noo.action.CANCEL_UPLOAD"
        const val EXTRA_FILES = "files" // JSON array of {uri, name, size}
        const val EXTRA_SERVER_URL = "serverUrl"
        const val EXTRA_USERNAME = "username"
        const val EXTRA_AUTH_HEADER = "authHeader"
        const val EXTRA_REMOTE_FOLDER = "remoteFolder"

        private const val CHANNEL_ID = "share_upload_v2"
        private const val NOTIFICATION_ID = 4201
    }

    private data class ShareFile(val uri: String, val name: String, val size: Long?)

    private data class UploadBatch(
        val files: List<ShareFile>,
        val serverUrl: String,
        val username: String,
        val authHeader: String,
        val remoteFolder: String,
    )

    @Volatile
    private var cancelled = false
    private val queue = TransferQueue<UploadBatch> { runUploads(it) }

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
        val remoteFolder = intent?.getStringExtra(EXTRA_REMOTE_FOLDER)
        if (filesJson == null || serverUrl == null || username == null ||
            authHeader == null || remoteFolder == null
        ) {
            stopSelf()
            return START_NOT_STICKY
        }

        NooNotificationChannels.ensure(
            this,
            CHANNEL_ID,
            "File uploads",
            // Default (not low) importance so a finished upload actually
            // alerts; the progress updates themselves stay silent below.
            NotificationManager.IMPORTANCE_DEFAULT,
            "Progress for files shared to Noo",
        )
        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            buildProgressNotification("Preparing to upload…", null, indeterminate = true),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            } else {
                0
            },
        )

        queue.enqueue(UploadBatch(parseFiles(filesJson), serverUrl, username, authHeader, remoteFolder))
        return START_NOT_STICKY
    }

    private fun parseFiles(json: String): List<ShareFile> {
        val arr = JSONArray(json)
        return (0 until arr.length()).map { i ->
            val obj = arr.getJSONObject(i)
            ShareFile(
                uri = obj.getString("uri"),
                name = obj.getString("name"),
                size = if (obj.isNull("size")) null else obj.getLong("size"),
            )
        }
    }

    private fun runUploads(batch: UploadBatch) {
        cancelled = false
        var succeeded = 0
        var failed = 0
        val cleanServer = batch.serverUrl.trimEnd('/')
        var cleanFolder = batch.remoteFolder.trim()
        if (!cleanFolder.startsWith("/")) cleanFolder = "/$cleanFolder"
        if (!cleanFolder.endsWith("/")) cleanFolder = "$cleanFolder/"

        for ((index, file) in batch.files.withIndex()) {
            if (cancelled) break
            val label = if (batch.files.size == 1) {
                file.name
            } else {
                "${file.name} (${index + 1}/${batch.files.size})"
            }
            var tempFile: File? = null
            try {
                notify(buildProgressNotification("Preparing $label…", null, indeterminate = true))
                tempFile = materialize(file) { sent, total ->
                    notify(
                        buildProgressNotification(
                            "Preparing $label…",
                            progressFraction(sent, total),
                            indeterminate = total == null,
                        ),
                    )
                }
                if (cancelled) break

                val encodedName = Uri.encode(file.name)
                val url = URL("$cleanServer/remote.php/dav/files/${batch.username}$cleanFolder$encodedName")
                val ok = DavTransfer.put(
                    url,
                    batch.authHeader,
                    tempFile,
                    contentType = "application/octet-stream",
                    onProgress = { sent, total ->
                        notify(
                            buildProgressNotification(
                                "Uploading $label…",
                                progressFraction(sent, total),
                                indeterminate = false,
                            ),
                        )
                    },
                    isCancelled = { cancelled },
                )
                if (ok) succeeded++ else failed++
            } catch (e: Exception) {
                failed++
            } finally {
                tempFile?.delete()
            }
        }

        val finalText = when {
            cancelled -> "Upload cancelled"
            failed == 0 && batch.files.size == 1 -> "Uploaded ${batch.files.first().name}"
            failed == 0 -> "Uploaded $succeeded of ${batch.files.size} files"
            else -> "Uploaded $succeeded of ${batch.files.size} files - $failed failed"
        }
        manager().notify(NOTIFICATION_ID, buildFinalNotification(finalText))
        // batch.remoteFolder, not the locally-normalized cleanFolder - Dart's
        // FilesController.currentFolderPath never carries the trailing
        // slash cleanFolder adds, so publishing the original value lets the
        // Dart side compare them directly with no reformatting of its own.
        if (succeeded > 0) {
            UploadEventBus.publishCompleted(batch.remoteFolder, succeeded, failed)
        }

        if (queue.pendingCount == 0) {
            stopForeground(STOP_FOREGROUND_DETACH)
            stopSelf()
        }
    }

    private fun progressFraction(sent: Long, total: Long?): Float? {
        if (total == null || total <= 0) return null
        return (sent.toFloat() / total.toFloat()).coerceIn(0f, 1f)
    }

    private fun materialize(file: ShareFile, onProgress: (Long, Long?) -> Unit): File {
        val uri = Uri.parse(file.uri)
        val target = File(cacheDir, "share_upload_${System.currentTimeMillis()}_${file.name}")
        contentResolver.openInputStream(uri)?.use { input ->
            FileOutputStream(target).use { output ->
                val buffer = ByteArray(256 * 1024)
                var sent = 0L
                var lastEmit = 0L
                while (!cancelled) {
                    val read = input.read(buffer)
                    if (read == -1) break
                    output.write(buffer, 0, read)
                    sent += read
                    val now = System.currentTimeMillis()
                    if (now - lastEmit >= 200) {
                        lastEmit = now
                        onProgress(sent, file.size)
                    }
                }
            }
        } ?: throw IllegalStateException("Could not open ${file.uri}")
        if (uri.scheme == "file") {
            val source = File(uri.path ?: "")
            val dropRoot = File(cacheDir, "incoming_drops").canonicalPath + File.separator
            if (source.canonicalPath.startsWith(dropRoot)) source.delete()
        }
        return target
    }

    private fun manager() =
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun notify(notification: Notification) {
        manager().notify(NOTIFICATION_ID, notification)
    }

    private fun buildProgressNotification(text: String, progress: Float?, indeterminate: Boolean): Notification {
        val cancelIntent = Intent(this, ShareUploadService::class.java).apply { action = ACTION_CANCEL }
        val cancelPendingIntent = PendingIntent.getService(
            this,
            0,
            cancelIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setContentTitle("Uploading to Noo")
            .setContentText(text)
            .setOnlyAlertOnce(true)
            .setSilent(true)
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
            .setSmallIcon(android.R.drawable.stat_sys_upload_done)
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
