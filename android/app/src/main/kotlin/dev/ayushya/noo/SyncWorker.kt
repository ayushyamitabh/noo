package dev.ayushya.noo

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.withLock
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

        // True for a user-initiated "Sync now": always does a full walk of
        // every root (never trusts the root-etag shortcut) and shows the
        // "Checking for changes..." notification immediately. False for
        // periodic/automatic runs, which stay silent unless something
        // actually transfers.
        const val KEY_FORCE = "force"

        // Whether automatic (non-force) runs may post progress/summary
        // notifications - the "Background sync notifications" setting.
        // Conflicts are always notified (they need a decision), and a
        // user-initiated run (force) always shows progress.
        const val KEY_NOTIFY = "notify"

        // Even when a root's etag hasn't changed, walk it in full at least
        // this often: etag propagation isn't reliable everywhere (external
        // storage mounts in particular), so this bounds how stale a mirror
        // can get if the cheap check is ever wrong.
        private const val FULL_WALK_MAX_AGE_MS = 6L * 60 * 60 * 1000

        // Pre-multi-account name of the single shared periodic job - only
        // kept so it can be cancelled when migrating to per-account jobs.
        const val UNIQUE_PERIODIC_NAME = "noo_sync_periodic"

        // Each account with sync enabled gets its own periodic job (with
        // that account's own credentials/paths/interval baked in), so
        // background sync works for every enabled account, not just
        // whichever one was active last.
        fun periodicNameFor(accountId: String) = "${UNIQUE_PERIODIC_NAME}_$accountId"
        fun oneOffNameFor(accountId: String) = "noo_sync_now_$accountId"

        // Low importance = no sound/vibration. Importance can't be changed
        // on an existing channel, hence the new id (the old "device_sync"
        // channel, which made noise, is deleted when this one is created).
        private const val CHANNEL_ID = "device_sync_v2"
        private const val LEGACY_CHANNEL_ID = "device_sync"

        // Notification ids are per account so two accounts syncing never
        // overwrite each other's progress/summary/conflict notifications.
        // Progress and the final summary share one id per account - the
        // summary's notify() call naturally replaces the ongoing progress
        // notification in place (no flicker of two separate notifications),
        // and if there was nothing to actually sync, doWork explicitly
        // cancels it since no summary gets posted to replace it.
        private const val SUMMARY_NOTIFICATION_ID_BASE = 100_000
        private const val CONFLICT_NOTIFICATION_ID_BASE = 200_000
        fun summaryNotificationId(accountId: String) =
            SUMMARY_NOTIFICATION_ID_BASE + (accountId.hashCode() and 0xFFFF)
        fun conflictNotificationId(accountId: String, relPath: String) =
            CONFLICT_NOTIFICATION_ID_BASE + ((accountId + "|" + relPath).hashCode() and 0xFFFF)
        private const val TAG = "NooSync"
    }

    // totalTransfers is only known once at least one path's been diffed -
    // grows across the run as each configured path is diffed in turn.
    private var totalTransfers = 0
    private var completedTransfers = 0
    private var progressShown = false

    // Set at the top of performSync - the notify* helpers below need the
    // account (for its notification ids / title) and whether this run may
    // show progress at all.
    private var notifyAccountId = ""
    private var notifyUsername = ""
    private var showProgressNotifications = true

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        // One sync at a time, app-wide - see SyncEngine.syncLock. A run that
        // has to wait just starts once the current one finishes.
        SyncEngine.syncLock.withLock { performSync() }
    }

    private suspend fun performSync(): Result = withContext(Dispatchers.IO) {
        val accountId = inputData.getString(KEY_ACCOUNT_ID) ?: return@withContext Result.failure()
        val serverUrl = inputData.getString(KEY_SERVER_URL) ?: return@withContext Result.failure()
        val username = inputData.getString(KEY_USERNAME) ?: return@withContext Result.failure()
        val authHeader = inputData.getString(KEY_AUTH_HEADER) ?: return@withContext Result.failure()
        val foldersJson = inputData.getString(KEY_FOLDERS) ?: "[]"
        val force = inputData.getBoolean(KEY_FORCE, false)
        notifyAccountId = accountId
        notifyUsername = username
        showProgressNotifications = force || inputData.getBoolean(KEY_NOTIFY, true)
        val folders = (0 until JSONArray(foldersJson).length()).map { JSONArray(foldersJson).getString(it) }
        Log.d(TAG, "doWork: account=$accountId server=$serverUrl user=$username folders=$folders")
        if (folders.isEmpty()) return@withContext Result.success()

        val syncRoot = SyncEngine.syncRoot(applicationContext, accountId)
        val state = SyncEngine.loadState(applicationContext, accountId).toMutableMap()
        val markers = SyncEngine.loadRootMarkers(applicationContext, accountId)

        var downloaded = 0
        var uploaded = 0
        var deleted = 0
        val conflicts = mutableListOf<Pair<SyncEngine.RemoteEntry, String>>()

        SyncStatusBus.setSyncing(accountId, true)
        // For a user-initiated run, shown immediately rather than lazily on
        // the first transfer - the PROPFIND walk/diff below (per configured
        // path, potentially recursive) can itself take real time, and the
        // user just asked for a sync so they expect to see it happening.
        // Automatic runs stay silent until something actually transfers.
        if (force) notifyProgress("Checking for changes…")
        try {
            for (path in folders) {
                try {
                    // A configured path can be a file or a folder now - check
                    // which before deciding whether to walk it recursively or
                    // just diff the single item.
                    val self = SyncEngine.propfindSelf(serverUrl, username, authHeader, path)
                    val pathPrefix = path.trimEnd('/') + "/"
                    val priorFileIdsForPath = state.filterValues {
                        it.relPath == path.trimStart('/') || it.relPath.startsWith(pathPrefix.trimStart('/'))
                    }.keys

                    // Cheap "did anything change?" check: an unchanged root etag
                    // means nothing beneath it changed on the server, and if
                    // every local file is also still exactly as recorded there's
                    // nothing to upload or re-download either - so skip the walk
                    // (one Depth-0 PROPFIND instead of one per subfolder).
                    val marker = markers[path]
                    if (!force && self != null && self.isFolder && marker != null &&
                        marker.etag == self.etag &&
                        System.currentTimeMillis() - marker.fullWalkAt < FULL_WALK_MAX_AGE_MS &&
                        priorFileIdsForPath.isNotEmpty() &&
                        SyncEngine.localMatchesState(state, priorFileIdsForPath, syncRoot)
                    ) {
                        Log.d(TAG, "skip $path: server etag unchanged, local intact")
                        continue
                    }

                    // The server says this synced path no longer exists (a
                    // clean 404, not a network error): flag it so the app drops
                    // it from the synced list instead of leaving a dead entry.
                    SyncEngine.setRootMissing(applicationContext, accountId, path, self == null)

                    val entries = when {
                        self == null -> emptyList()
                        self.isFolder -> SyncEngine.walkRemoteTree(serverUrl, username, authHeader, path)
                        else -> listOf(self)
                    }
                    var pathClean = true

                    val actions = SyncEngine.diffFolder(entries, state, priorFileIdsForPath, syncRoot)
                    totalTransfers += actions.count {
                        it is SyncEngine.SyncAction.Download || it is SyncEngine.SyncAction.Upload
                    }
                    for (action in actions) {
                        when (action) {
                            is SyncEngine.SyncAction.Download -> {
                                val relPath = action.entry.path.removePrefix("/")
                                notifyProgress(relPath.substringAfterLast('/'))
                                SyncStatusBus.markFileSyncing(accountId, action.entry.fileId, true)
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
                                } else {
                                    pathClean = false
                                }
                                SyncStatusBus.markFileSyncing(accountId, action.entry.fileId, false)
                                completedTransfers++
                            }
                            is SyncEngine.SyncAction.Upload -> {
                                notifyProgress(action.relPath.substringAfterLast('/'))
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
                                } else {
                                    pathClean = false
                                }
                                SyncStatusBus.markFileSyncing(accountId, action.fileId, false)
                                completedTransfers++
                            }
                            is SyncEngine.SyncAction.Delete -> {
                                // Only counts toward the "removed" summary if a
                                // local copy actually existed and was deleted -
                                // dropping stale state for a file that was never
                                // on disk isn't a removal the user should hear
                                // about.
                                val localFile = File(syncRoot, action.relPath)
                                if (localFile.exists() && localFile.delete()) deleted++
                                state.remove(action.fileId)
                            }
                            is SyncEngine.SyncAction.Conflict -> {
                                conflicts.add(action.entry to action.relPath)
                                pathClean = false
                            }
                        }
                    }

                    // Mirror the folder structure itself: empty folders
                    // created on the server appear on device, and folders
                    // deleted on the server (whose files the diff above has
                    // already removed) don't linger as empty directories.
                    if (self == null || self.isFolder) {
                        val rootRel = path.trim('/')
                        if (self != null) SyncEngine.mirrorFolders(entries, syncRoot, rootRel)
                        val remoteFolders = entries.filter { it.isFolder }
                            .map { it.path.trim('/') }
                            .toMutableSet()
                        if (self != null) remoteFolders.add(rootRel)
                        SyncEngine.pruneRemovedFolders(syncRoot, rootRel, remoteFolders)
                    }

                    // Only remember this root's etag once the whole path synced
                    // without a hitch - anything left over (a failed transfer, an
                    // unresolved conflict) has to be retried by a real walk next
                    // time, not skipped because the etag "hasn't changed".
                    if (self != null && self.isFolder && pathClean) {
                        markers[path] = SyncEngine.RootMarker(self.etag, System.currentTimeMillis())
                    } else {
                        markers.remove(path)
                    }
                } catch (e: SyncEngine.RemoteUnavailableException) {
                  // Couldn't reach the server for this path - leave its state
                  // and marker untouched and try again next run. Crucially,
                  // never diff against an empty listing here: that would look
                  // like the whole folder was deleted server-side.
                  Log.w(TAG, "skipping $path this run: ${e.message}")
                }
            }
        } finally {
            markers.keys.retainAll(folders.toSet())
            SyncEngine.saveRootMarkers(applicationContext, accountId, markers)
            // State must be saved *before* announcing that syncing has
            // stopped - `syncStatusMap` (MainActivity.kt) recomputes
            // `syncedFileIds` fresh from `SyncEngine.loadState` every time
            // this bus publishes, so publishing first would hand Dart a
            // snapshot that's still missing every file this run just
            // downloaded, and nothing would ever correct it afterward
            // (no further bus event fires post-save) - newly-synced files
            // would never show their "synced" badge until the next app
            // restart forced a fresh `getStatus()` read.
            SyncEngine.saveState(applicationContext, accountId, state)
            SyncStatusBus.setSyncing(accountId, false)
        }

        Log.d(
            TAG,
            "doWork done: downloaded=$downloaded uploaded=$uploaded deleted=$deleted conflicts=${conflicts.size}",
        )

        if ((downloaded > 0 || uploaded > 0 || deleted > 0) && showProgressNotifications) {
            // Replaces the ongoing progress notification in place (same
            // ID) with a final, dismissible summary.
            notifySummary(downloaded, uploaded, deleted)
        } else if (progressShown) {
            // Nothing actually transferred (e.g. every diffed action was a
            // Delete/Conflict, or the progress notification was shown for a
            // run that ended up empty) - nothing to replace it with, so
            // just clear it rather than leaving a stale "Syncing…" behind.
            manager().cancel(summaryNotificationId(accountId))
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

    /// Called once immediately at the start of every run that actually has
    /// folders configured (covers the PROPFIND walk/diff phase, which can
    /// itself take real time), then again per file as transfers happen.
    /// `totalTransfers` grows as each configured path is diffed (paths are
    /// diffed one at a time), so early on this shows an indeterminate bar;
    /// it becomes determinate once the true total for this run is known. A
    /// run that turns out to have nothing to transfer cancels this
    /// notification at the end instead of leaving it stuck (see the
    /// `progressShown` check in `doWork`).
    private fun notifyProgress(fileName: String) {
        if (!showProgressNotifications) return
        progressShown = true
        createChannel()
        val text = if (totalTransfers > 1) {
            "$fileName (${completedTransfers + 1}/$totalTransfers)"
        } else {
            fileName
        }
        val builder = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentTitle("Syncing to device · $notifyUsername")
            .setContentText(text)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setOngoing(true)
        if (totalTransfers > 0) {
            builder.setProgress(totalTransfers, completedTransfers, false)
        } else {
            builder.setProgress(0, 0, true)
        }
        manager().notify(summaryNotificationId(notifyAccountId), builder.build())
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
            .setContentTitle("Noo sync · $notifyUsername")
            .setContentText(text)
            .setAutoCancel(true)
            .setSilent(true)
            .build()
        manager().notify(summaryNotificationId(notifyAccountId), notification)
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
            val notificationId = conflictNotificationId(accountId, relPath)

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
                .setContentText("$username - changed both on this device and on the server.")
                .setAutoCancel(true)
                .setSilent(true)
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
        val requestCode = (accountId + relPath + resolution).hashCode()
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
        NooNotificationChannels.ensure(
            applicationContext,
            CHANNEL_ID,
            "Device sync",
            NotificationManager.IMPORTANCE_LOW,
            "Updates and conflicts for folders synced to this device",
            legacyIds = listOf(LEGACY_CHANNEL_ID),
        )
    }
}
