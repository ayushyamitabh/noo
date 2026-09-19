package dev.ayushya.noo

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationManagerCompat

/**
 * Handles the "Keep local" / "Use server" actions on a sync-conflict
 * notification (see `SyncWorker.notifyConflicts`). A `BroadcastReceiver`
 * can't block on network itself (~10s execution budget), so this only
 * dismisses the notification and hands off to a one-shot
 * [ConflictResolveWorker] for the actual upload/download.
 */
class SyncConflictReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_RESOLVE = "dev.ayushya.noo.action.RESOLVE_SYNC_CONFLICT"
        const val EXTRA_ACCOUNT_ID = "accountId"
        const val EXTRA_SERVER_URL = "serverUrl"
        const val EXTRA_USERNAME = "username"
        const val EXTRA_AUTH_HEADER = "authHeader"
        const val EXTRA_FILE_ID = "fileId"
        const val EXTRA_REMOTE_PATH = "remotePath"
        const val EXTRA_REL_PATH = "relPath"
        const val EXTRA_RESOLUTION = "resolution" // "local" | "server"
        const val EXTRA_NOTIFICATION_ID = "notificationId"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_RESOLVE) return

        val notificationId = intent.getIntExtra(EXTRA_NOTIFICATION_ID, -1)
        if (notificationId != -1) {
            NotificationManagerCompat.from(context).cancel(notificationId)
        }

        ConflictResolveWorker.enqueue(
            context,
            accountId = intent.getStringExtra(EXTRA_ACCOUNT_ID),
            serverUrl = intent.getStringExtra(EXTRA_SERVER_URL),
            username = intent.getStringExtra(EXTRA_USERNAME),
            authHeader = intent.getStringExtra(EXTRA_AUTH_HEADER),
            fileId = intent.getStringExtra(EXTRA_FILE_ID),
            remotePath = intent.getStringExtra(EXTRA_REMOTE_PATH),
            relPath = intent.getStringExtra(EXTRA_REL_PATH),
            resolution = intent.getStringExtra(EXTRA_RESOLUTION),
        )
    }
}
