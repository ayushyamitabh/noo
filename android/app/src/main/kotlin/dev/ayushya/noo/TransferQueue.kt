package dev.ayushya.noo

import java.util.concurrent.LinkedBlockingQueue

/**
 * A tiny sequential work queue for [DownloadService]/[ShareUploadService]:
 * each enqueued batch runs to completion before the next starts, instead
 * of a second batch arriving mid-transfer being silently dropped - the
 * previous behavior both services independently accepted as a known
 * limitation (see their old doc comments). One daemon worker thread,
 * started lazily on first use and parked on the queue for the life of the
 * process.
 */
class TransferQueue<T>(private val process: (T) -> Unit) {
    private val queue = LinkedBlockingQueue<T>()

    @Volatile
    private var started = false

    /** How many batches (including whatever's currently running) are queued. */
    val pendingCount: Int
        get() = queue.size

    @Synchronized
    fun enqueue(batch: T) {
        queue.put(batch)
        if (!started) {
            started = true
            Thread {
                while (true) {
                    process(queue.take())
                }
            }.apply { isDaemon = true }.start()
        }
    }

    /** Drops every batch that hasn't started running yet (not the current one). */
    fun clearPending() {
        queue.clear()
    }
}
