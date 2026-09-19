package dev.ayushya.noo

/**
 * In-memory, in-process pub/sub for live device-sync status -
 * [SyncWorker]/[ConflictResolveWorker] publish into this, `MainActivity`'s
 * `dev.ayushya.noo/sync_service/status` EventChannel forwards it to Dart.
 * Plain in-memory state is enough (no IPC/persistence needed) since the
 * workers and the Activity always run in the same process; contrast with
 * [SyncEngine]'s on-disk per-account state map, which *is* durable and is
 * what actually answers "is this file synced" (this bus only ever tracks
 * the transient "syncing right now" / "unresolved conflict" parts of that
 * picture).
 */
object SyncStatusBus {
    data class Conflict(
        val accountId: String,
        val fileId: String,
        val remotePath: String,
        val relPath: String,
        val name: String,
    )

    data class Status(
        val accountId: String?,
        val syncing: Boolean,
        val syncingFileIds: Set<String>,
        val conflicts: List<Conflict>,
    )

    @Volatile
    private var current = Status(accountId = null, syncing = false, syncingFileIds = emptySet(), conflicts = emptyList())
    private val listeners = mutableListOf<(Status) -> Unit>()

    @Synchronized
    fun subscribe(listener: (Status) -> Unit) {
        listeners.add(listener)
        listener(current)
    }

    @Synchronized
    fun unsubscribe(listener: (Status) -> Unit) {
        listeners.remove(listener)
    }

    fun snapshot(): Status = current

    @Synchronized
    fun setSyncing(accountId: String, syncing: Boolean) {
        current = current.copy(accountId = accountId, syncing = syncing)
        if (!syncing) current = current.copy(syncingFileIds = emptySet())
        publish()
    }

    @Synchronized
    fun markFileSyncing(accountId: String, fileId: String, syncing: Boolean) {
        val ids = current.syncingFileIds.toMutableSet()
        if (syncing) ids.add(fileId) else ids.remove(fileId)
        current = current.copy(accountId = accountId, syncingFileIds = ids)
        publish()
    }

    @Synchronized
    fun addConflicts(accountId: String, newConflicts: List<Conflict>) {
        if (newConflicts.isEmpty()) return
        val existingIds = current.conflicts.map { it.fileId }.toSet()
        val merged = current.conflicts + newConflicts.filter { it.fileId !in existingIds }
        current = current.copy(accountId = accountId, conflicts = merged)
        publish()
    }

    @Synchronized
    fun removeConflict(accountId: String, fileId: String) {
        current = current.copy(accountId = accountId, conflicts = current.conflicts.filter { it.fileId != fileId })
        publish()
    }

    private fun publish() {
        listeners.toList().forEach { it(current) }
    }
}
