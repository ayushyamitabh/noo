package dev.ayushya.noo

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build

/**
 * Shared notification-channel creation - [DownloadService],
 * [ShareUploadService], and [SyncWorker] each independently re-implemented
 * this same `if (SDK_INT >= O) { NotificationChannel(...); create }` shape
 * before this existed.
 */
object NooNotificationChannels {
    fun ensure(
        context: Context,
        id: String,
        name: String,
        importance: Int,
        description: String,
        // Old channel ids this one replaces. A channel's importance (and so
        // whether it makes sound) can't be changed once it's been created -
        // Android ignores later changes - so changing it means moving to a
        // new id and removing the old channel.
        legacyIds: List<String> = emptyList(),
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        legacyIds.forEach { manager.deleteNotificationChannel(it) }
        val channel = NotificationChannel(id, name, importance).apply {
            this.description = description
            if (importance <= NotificationManager.IMPORTANCE_LOW) {
                setSound(null, null)
                enableVibration(false)
            }
        }
        manager.createNotificationChannel(channel)
    }
}
