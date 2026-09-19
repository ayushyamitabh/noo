package dev.ayushya.noo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import java.io.File

/**
 * The periodic (and manual "Sync now") device-sync job. Runs entirely
 * independent of the Flutter engine (see [SyncEngine]'s doc comment) -
 * enqueued/re-enqueued from `MainActivity.kt`'s
 * `dev.ayushya.noo/sync_service` MethodChannel whenever the synced-folder
 * list, account, or network setting changes, since a periodic
 * `WorkRequest`'s input `Data` is fixed at enqueue time.
 */
class SyncWorker(appContext: Context, params: WorkerParameters) :
    CoroutineWorker(appContext, params) {

    companion object {
        const val KEY_ACCOUNT_ID = "accountId"
        const val KEY_SERVER_URL = "serverUrl"
        const val KEY_USERNAME = "username"
        const val KEY_AUTH_HEADER = "authHeader"
        const val KEY_FOLDERS = "folders" // JSON array of remote file/folder paths

        const val UNIQUE_PERIODIC_NAME = "noo_sync_periodic"
        const val UNIQUE_ONE_OFF_NAME = "noo_sync_now"

        private const val CHANNEL_ID = "device_sync"
        private const val SUMMARY_NOTIFICATION_ID = 4401
        private const val CONFLICT_NOTIFICATION_ID_BASE = 4500
        private const val TAG = "NooSync"
    }

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val accountId = inputData.getString(KEY_ACCOUNT_ID) ?: return@withContext Result.failure()
        val serverUrl = inputData.getString(KEY_SERVER_URL) ?: return@withContext Result.failure()
        val username = inputData.getString(KEY_USERNAME) ?: return@withContext Result.failure()
        val authHeader = inputData.getString(KEY_AUTH_HEADER) ?: return@withContext Result.failure()
        val foldersJson = inputData.getString(KEY_FOLDERS) ?: "[]"
        val folders = (0 until JSONArray(foldersJson).length()).map { JSONArray(foldersJson).getString(it) }
        Log.d(TAG, "doWork: account=$accountId server=$serverUrl user=$username folders=$folders")
        if (folders.isEmpty()) return@withContext Result.success()

        val syncRoot = SyncEngine.syncRoot(applicationContext, accountId)
        val state = SyncEngine.loadState(applicationContext, accountId).toMutableMap()

        var downloaded = 0
        var uploaded = 0
        var deleted = 0
        val conflicts = mutableListOf<Pair<SyncEngine.RemoteEntry, String>>()

        SyncStatusBus.setSyncing(accountId, true)
        try {
            for (path in folders) {
                // A configured path can be a file or a folder now - check
                // which before deciding whether to walk it recursively or
                // just diff the single item.
                val self = SyncEngine.propfindSelf(serverUrl, username, authHeader, path)
                val entries = when {
                    self == null -> emptyList()
                    self.isFolder -> SyncEngine.walkRemoteTree(serverUrl, username, authHeader, path)
                    else -> listOf(self)
                }
                val pathPrefix = path.trimEnd('/') + "/"
                val priorFileIdsForPath = state.filterValues {
                    it.relPath == path.trimStart('/') || it.relPath.startsWith(pathPrefix.trimStart('/'))
                }.keys

                val actions = SyncEngine.diffFolder(entries, state, priorFileIdsForPath, syncRoot)
                for (action in actions) {
                    when (action) {
                        is SyncEngine.SyncAction.Download -> {
                            SyncStatusBus.markFileSyncing(accountId, action.entry.fileId, true)
                            val relPath = action.entry.path.removePrefix("/")
                            val dest = File(syncRoot, relPath)
                            if (SyncEngine.downloadFile(serverUrl, username, authHeader, action.entry.path, dest)) {
                                state[action.entry.fileId] = SyncEngine.FileState(
                                    relPath = relPath,
                                    etag = action.entry.etag,
                                    lastModified = action.entry.lastModified,
                                    size = action.entry.size,
                                    localMTime = dest.lastModified(),
                                )
                                downloaded++
                            }
                            SyncStatusBus.markFileSyncing(accountId, action.entry.fileId, false)
                        }
                        is SyncEngine.SyncAction.Upload -> {
                            SyncStatusBus.markFileSyncing(accountId, action.fileId, true)
                            val localFile = File(syncRoot, action.relPath)
                            val remotePath = "/${action.relPath}"
                            if (localFile.exists() &&
                                SyncEngine.uploadFile(serverUrl, username, authHeader, remotePath, localFile)
                            ) {
                                val prior = state[action.fileId]
                                state[action.fileId] = SyncEngine.FileState(
                                    relPath = action.relPath,
                                    etag = prior?.etag ?: "",
                                    lastModified = localFile.lastModified(),
                                    size = localFile.length(),
                                    localMTime = localFile.lastModified(),
                                )
                                uploaded++
                            }
                            SyncStatusBus.markFileSyncing(accountId, action.fileId, false)
                        }
                        is SyncEngine.SyncAction.Delete -> {
                            File(syncRoot, action.relPath).delete()
                            state.remove(action.fileId)
                            deleted++
                        }
                        is SyncEngine.SyncAction.Conflict -> conflicts.add(action.entry to action.relPath)
                    }
                }
            }
        } finally {
            SyncStatusBus.setSyncing(accountId, false)
        }

        SyncEngine.saveState(applicationContext, accountId, state)
        Log.d(
            TAG,
            "doWork done: downloaded=$downloaded uploaded=$uploaded deleted=$deleted conflicts=${conflicts.size}",
        )

        if (downloaded > 0 || uploaded > 0 || deleted > 0) {
            notifySummary(downloaded, uploaded, deleted)
        }
        if (conflicts.isNotEmpty()) {
            SyncStatusBus.addConflicts(
                accountId,
                conflicts.map { (entry, relPath) ->
                    SyncStatusBus.Conflict(
                        accountId = accountId,
                        fileId = entry.fileId,
                        remotePath = entry.path,
                        relPath = relPath,
                        name = relPath.substringAfterLast('/'),
                    )
                },
            )
            notifyConflicts(accountId, serverUrl, username, authHeader, conflicts)
        }

        Result.success()
    }

    private fun notifySummary(downloaded: Int, uploaded: Int, deleted: Int) {
        createChannel()
        val parts = mutableListOf<String>()
        if (downloaded > 0) parts.add("$downloaded updated")
        if (uploaded > 0) parts.add("$uploaded uploaded")
        if (deleted > 0) parts.add("$deleted removed")
        val text = parts.joinToString(", ")

        val notification = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentTitle("Noo sync")
            .setContentText(text)
            .setAutoCancel(true)
            .build()
        manager().notify(SUMMARY_NOTIFICATION_ID, notification)
    }

    private fun notifyConflicts(
        accountId: String,
        serverUrl: String,
        username: String,
        authHeader: String,
        conflicts: List<Pair<SyncEngine.RemoteEntry, String>>,
    ) {
        createChannel()
        for ((index, conflict) in conflicts.withIndex()) {
            val (entry, relPath) = conflict
            val fileName = relPath.substringAfterLast('/')
            val notificationId = CONFLICT_NOTIFICATION_ID_BASE + (relPath.hashCode() and 0xFFFF)

            val useLocalIntent = conflictActionIntent(
                accountId,
                serverUrl,
                username,
                authHeader,
                entry.fileId,
                entry.path,
                relPath,
                "local",
                notificationId,
            )
            val useServerIntent = conflictActionIntent(
                accountId,
                serverUrl,
                username,
                authHeader,
                entry.fileId,
                entry.path,
                relPath,
                "server",
                notificationId,
            )

            val notification = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.stat_notify_error)
                .setContentTitle("Sync conflict: $fileName")
                .setContentText("Changed both on this device and on the server.")
                .setAutoCancel(true)
                .addAction(0, "Keep local", useLocalIntent)
                .addAction(0, "Use server", useServerIntent)
                .build()
            manager().notify(notificationId, notification)
        }
    }

    private fun conflictActionIntent(
        accountId: String,
        serverUrl: String,
        username: String,
        authHeader: String,
        fileId: String,
        remotePath: String,
        relPath: String,
        resolution: String,
        notificationId: Int,
    ): PendingIntent {
        val intent = Intent(applicationContext, SyncConflictReceiver::class.java).apply {
            action = SyncConflictReceiver.ACTION_RESOLVE
            putExtra(SyncConflictReceiver.EXTRA_ACCOUNT_ID, accountId)
            putExtra(SyncConflictReceiver.EXTRA_SERVER_URL, serverUrl)
            putExtra(SyncConflictReceiver.EXTRA_USERNAME, username)
            putExtra(SyncConflictReceiver.EXTRA_AUTH_HEADER, authHeader)
            putExtra(SyncConflictReceiver.EXTRA_FILE_ID, fileId)
            putExtra(SyncConflictReceiver.EXTRA_REMOTE_PATH, remotePath)
            putExtra(SyncConflictReceiver.EXTRA_REL_PATH, relPath)
            putExtra(SyncConflictReceiver.EXTRA_RESOLUTION, resolution)
            putExtra(SyncConflictReceiver.EXTRA_NOTIFICATION_ID, notificationId)
        }
        // Request code must be unique per (file, resolution) pair, else the
        // two actions' PendingIntents collide and only one survives.
        val requestCode = (relPath + resolution).hashCode()
        return PendingIntent.getBroadcast(
            applicationContext,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun manager() =
        applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Device sync",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply { description = "Updates and conflicts for folders synced to this device" }
            manager().createNotificationChannel(channel)
        }
    }
}
