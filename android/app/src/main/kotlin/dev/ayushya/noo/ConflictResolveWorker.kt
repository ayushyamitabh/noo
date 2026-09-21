package dev.ayushya.noo

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Resolves one sync conflict, triggered either by [SyncConflictReceiver]
 * (a notification action) or directly from Dart (in-app resolution via the
 * `dev.ayushya.noo/sync_service` MethodChannel's `resolveConflict`, see
 * `MainActivity.kt`) - "local" pushes the on-device copy up (overwriting
 * the server), "server" pulls the server copy down (overwriting the local
 * mirror). Either way, the sync-state entry for this file is refreshed
 * afterward so the next [SyncWorker] pass doesn't immediately re-flag it.
 */
class ConflictResolveWorker(appContext: Context, params: WorkerParameters) :
    CoroutineWorker(appContext, params) {

    companion object {
        const val KEY_ACCOUNT_ID = "accountId"
        const val KEY_SERVER_URL = "serverUrl"
        const val KEY_USERNAME = "username"
        const val KEY_AUTH_HEADER = "authHeader"
        const val KEY_FILE_ID = "fileId"
        const val KEY_REMOTE_PATH = "remotePath"
        const val KEY_REL_PATH = "relPath"
        const val KEY_RESOLUTION = "resolution"

        /** The one place a resolution gets enqueued - both callers above share it. */
        fun enqueue(
            context: Context,
            accountId: String?,
            serverUrl: String?,
            username: String?,
            authHeader: String?,
            fileId: String?,
            remotePath: String?,
            relPath: String?,
            resolution: String?,
        ) {
            val data = workDataOf(
                KEY_ACCOUNT_ID to accountId,
                KEY_SERVER_URL to serverUrl,
                KEY_USERNAME to username,
                KEY_AUTH_HEADER to authHeader,
                KEY_FILE_ID to fileId,
                KEY_REMOTE_PATH to remotePath,
                KEY_REL_PATH to relPath,
                KEY_RESOLUTION to resolution,
            )
            val request = OneTimeWorkRequestBuilder<ConflictResolveWorker>()
                .setInputData(data)
                .build()
            WorkManager.getInstance(context).enqueue(request)
        }
    }

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        // Same lock as SyncWorker: both load/mutate/save the whole state map.
        SyncEngine.syncLock.withLock { performResolve() }
    }

    private suspend fun performResolve(): Result = withContext(Dispatchers.IO) {
        val accountId = inputData.getString(KEY_ACCOUNT_ID) ?: return@withContext Result.failure()
        val serverUrl = inputData.getString(KEY_SERVER_URL) ?: return@withContext Result.failure()
        val username = inputData.getString(KEY_USERNAME) ?: return@withContext Result.failure()
        val authHeader = inputData.getString(KEY_AUTH_HEADER) ?: return@withContext Result.failure()
        val fileId = inputData.getString(KEY_FILE_ID) ?: return@withContext Result.failure()
        val remotePath = inputData.getString(KEY_REMOTE_PATH) ?: return@withContext Result.failure()
        val relPath = inputData.getString(KEY_REL_PATH) ?: return@withContext Result.failure()
        val resolution = inputData.getString(KEY_RESOLUTION) ?: return@withContext Result.failure()

        val syncRoot = SyncEngine.syncRoot(applicationContext, accountId)
        val localFile = File(syncRoot, relPath)
        val ok = when (resolution) {
            "local" -> localFile.exists() &&
                SyncEngine.uploadFile(serverUrl, username, authHeader, remotePath, localFile)
            "server" -> SyncEngine.downloadFile(serverUrl, username, authHeader, remotePath, localFile)
            else -> false
        }
        if (!ok) return@withContext Result.retry()

        // Refresh the recorded state from the server's post-resolution
        // etag, so this file isn't immediately re-flagged as a conflict on
        // the next sync pass.
        val fresh = runCatching {
            SyncEngine.propfindSelf(serverUrl, username, authHeader, remotePath)
        }.getOrNull()
        val state = SyncEngine.loadState(applicationContext, accountId).toMutableMap()
        state[fileId] = SyncEngine.FileState(
            relPath = relPath,
            etag = fresh?.etag ?: "",
            lastModified = fresh?.lastModified ?: 0L,
            size = localFile.length(),
            localMTime = localFile.lastModified(),
        )
        SyncEngine.saveState(applicationContext, accountId, state)
        SyncStatusBus.removeConflict(accountId, fileId)

        Result.success()
    }
}
