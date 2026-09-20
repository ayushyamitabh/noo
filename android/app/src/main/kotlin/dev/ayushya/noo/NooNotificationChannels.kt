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
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(id, name, importance).apply {
            this.description = description
        }
        manager.createNotificationChannel(channel)
    }
}
