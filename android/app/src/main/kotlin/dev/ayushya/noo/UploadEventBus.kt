package dev.ayushya.noo

/**
 * In-memory, in-process pub/sub for "an upload batch just finished" -
 * [ShareUploadService] publishes into this, `MainActivity`'s
 * `dev.ayushya.noo/upload_service/status` EventChannel forwards it to Dart
 * so `FilesController` can refresh the destination folder if it's the one
 * currently on screen, without a manual pull-to-refresh. See
 * [SyncStatusBus]'s identical shape/rationale - the service and the
 * Activity always run in the same process, so plain in-memory pub/sub is
 * enough. Unlike that bus, this only ever carries discrete "just finished"
 * events, not ongoing state, so there's nothing to replay to a listener
 * that subscribes late.
 */
object UploadEventBus {
    data class Completed(
        val remoteFolder: String,
        val succeeded: Int,
        val failed: Int,
    )

    private val listeners = mutableListOf<(Completed) -> Unit>()

    @Synchronized
    fun subscribe(listener: (Completed) -> Unit) {
        listeners.add(listener)
    }

    @Synchronized
    fun unsubscribe(listener: (Completed) -> Unit) {
        listeners.remove(listener)
    }

    @Synchronized
    fun publishCompleted(remoteFolder: String, succeeded: Int, failed: Int) {
        val event = Completed(remoteFolder, succeeded, failed)
        listeners.toList().forEach { it(event) }
    }
}
