package dev.ayushya.noo

import android.app.Notification
import android.app.NotificationChannel
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
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Foreground service that prepares (copies from a content:// Uri) and
 * uploads one or more "Share to Noo" files over WebDAV, independent of
 * MainActivity/the Flutter engine being alive - the whole point is that
 * closing the app right after confirming a destination in ShareUploadView
 * doesn't interrupt the upload, the same way a file-manager app's own
 * upload notification survives the app being closed.
 *
 * Re-implements a plain WebDAV PUT here in Kotlin (HttpURLConnection, no
 * new HTTP dependency) rather than reusing NextcloudService/Dio from Dart,
 * since a Dart isolate doesn't keep running once the Flutter engine/
 * Activity are gone - only a real Android Service does. This does mean the
 * PUT request itself is duplicated logic (see NextcloudService.
 * uploadFileFromPath); keep both in sync if the upload semantics change.
 *
 * Started via the `dev.ayushya.noo/upload_service` MethodChannel
 * (MainActivity.kt) with credentials/destination passed as Intent extras -
 * never has an Activity in the loop after that. Shows one persistent,
 * cancellable notification for the whole batch; the Cancel action re-enters
 * this same running service instance with [ACTION_CANCEL], which the
 * copy/upload loops poll.
 */
class ShareUploadService : Service() {
    companion object {
        const val ACTION_CANCEL = "dev.ayushya.noo.action.CANCEL_UPLOAD"
        const val EXTRA_FILES = "files" // JSON array of {uri, name, size}
        const val EXTRA_SERVER_URL = "serverUrl"
        const val EXTRA_USERNAME = "username"
        const val EXTRA_AUTH_HEADER = "authHeader"
        const val EXTRA_REMOTE_FOLDER = "remoteFolder"

        private const val CHANNEL_ID = "share_upload"
        private const val NOTIFICATION_ID = 4201
    }

    private val cancelled = AtomicBoolean(false)
    private var uploadThread: Thread? = null

    private data class ShareFile(val uri: String, val name: String, val size: Long?)

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
        val remoteFolder = intent?.getStringExtra(EXTRA_REMOTE_FOLDER)
        if (filesJson == null || serverUrl == null || username == null ||
            authHeader == null || remoteFolder == null
        ) {
            stopSelf()
            return START_NOT_STICKY
        }

        createNotificationChannel()
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

        // A second share arriving mid-upload is dropped rather than queued -
        // rare in practice (sharing again before the first batch finishes),
        // not worth a real queue for.
        if (uploadThread == null) {
            val files = parseFiles(filesJson)
            uploadThread = Thread {
                runUploads(files, serverUrl, username, authHeader, remoteFolder)
            }.also { it.start() }
        }

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

    private fun runUploads(
        files: List<ShareFile>,
        serverUrl: String,
        username: String,
        authHeader: String,
        remoteFolder: String,
    ) {
        var succeeded = 0
        var failed = 0
        val cleanServer = serverUrl.trimEnd('/')
        var cleanFolder = remoteFolder.trim()
        if (!cleanFolder.startsWith("/")) cleanFolder = "/$cleanFolder"
        if (!cleanFolder.endsWith("/")) cleanFolder = "$cleanFolder/"

        for ((index, file) in files.withIndex()) {
            if (cancelled.get()) break
            val label = if (files.size == 1) file.name else "${file.name} (${index + 1}/${files.size})"
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
                if (cancelled.get()) break

                val encodedName = Uri.encode(file.name)
                val url = URL("$cleanServer/remote.php/dav/files/$username$cleanFolder$encodedName")
                val ok = uploadFile(tempFile, url, authHeader) { sent, total ->
                    notify(
                        buildProgressNotification(
                            "Uploading $label…",
                            progressFraction(sent, total),
                            indeterminate = false,
                        ),
                    )
                }
                if (ok) succeeded++ else failed++
            } catch (e: Exception) {
                failed++
            } finally {
                tempFile?.delete()
            }
        }

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val finalText = when {
            cancelled.get() -> "Upload cancelled"
            failed == 0 && files.size == 1 -> "Uploaded ${files.first().name}"
            failed == 0 -> "Uploaded $succeeded of ${files.size} files"
            else -> "Uploaded $succeeded of ${files.size} files - $failed failed"
        }
        manager.notify(NOTIFICATION_ID, buildFinalNotification(finalText))

        stopForeground(STOP_FOREGROUND_DETACH)
        stopSelf()
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
                while (!cancelled.get()) {
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
        return target
    }

    private fun uploadFile(
        file: File,
        url: URL,
        authHeader: String,
        onProgress: (Long, Long) -> Unit,
    ): Boolean {
        val length = file.length()
        val connection = url.openConnection() as HttpURLConnection
        return try {
            connection.requestMethod = "PUT"
            connection.doOutput = true
            connection.setFixedLengthStreamingMode(length)
            connection.setRequestProperty("Authorization", authHeader)
            connection.setRequestProperty("OCS-APIRequest", "true")
            connection.setRequestProperty("Content-Type", "application/octet-stream")
            connection.connectTimeout = 15000
            connection.readTimeout = 30000

            connection.outputStream.use { output ->
                file.inputStream().use { input ->
                    val buffer = ByteArray(256 * 1024)
                    var sent = 0L
                    var lastEmit = 0L
                    while (!cancelled.get()) {
                        val read = input.read(buffer)
                        if (read == -1) break
                        output.write(buffer, 0, read)
                        sent += read
                        val now = System.currentTimeMillis()
                        if (now - lastEmit >= 200) {
                            lastEmit = now
                            onProgress(sent, length)
                        }
                    }
                }
            }
            if (cancelled.get()) {
                false
            } else {
                val code = connection.responseCode
                code == 201 || code == 204 || code == 200
            }
        } catch (e: Exception) {
            false
        } finally {
            connection.disconnect()
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
                "File uploads",
                NotificationManager.IMPORTANCE_LOW,
            ).apply { description = "Progress for files shared to Noo" }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
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
        cancelled.set(true)
        super.onDestroy()
    }
}
