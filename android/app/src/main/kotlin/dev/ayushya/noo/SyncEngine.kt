package dev.ayushya.noo

import android.content.Context
import android.net.Uri
import android.util.Log
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.concurrent.TimeUnit
import javax.xml.parsers.DocumentBuilderFactory
import org.w3c.dom.Element

/**
 * The actual WebDAV walk/diff/GET/PUT engine for device sync - shared by
 * [SyncWorker] (periodic/manual full-folder sync) and
 * [ConflictResolveWorker] (single-file resolution from a notification
 * action), since both need the same PROPFIND/GET/PUT primitives and the
 * same on-disk sync-state bookkeeping.
 *
 * Deliberately plain Kotlin over `HttpURLConnection`, not
 * `NextcloudService`'s Dart/Dio code - this has to run from a
 * [androidx.work.CoroutineWorker], independent of the Flutter engine even
 * being loaded, the same reason `DownloadService.kt`/`ShareUploadService.kt`
 * re-implement GET/PUT natively instead of calling back into Dart.
 */
object SyncEngine {
    data class RemoteEntry(
        val path: String,
        val fileId: String,
        val etag: String,
        val lastModified: Long,
        val size: Long,
        val isFolder: Boolean,
    )

    data class FileState(
        val relPath: String,
        val etag: String,
        val lastModified: Long,
        val size: Long,
        val localMTime: Long,
    )

    sealed class SyncAction {
        data class Download(val entry: RemoteEntry) : SyncAction()
        data class Upload(val relPath: String, val fileId: String) : SyncAction()
        data class Delete(val relPath: String, val fileId: String) : SyncAction()
        data class Conflict(val entry: RemoteEntry, val relPath: String) : SyncAction()
    }

    private const val TAG = "NooSync"
    private const val STATE_PREFS = "noo_sync_state"
    private val rfc1123 =
        SimpleDateFormat("EEE, dd MMM yyyy HH:mm:ss zzz", Locale.US)

    // Only used for PROPFIND - unlike HttpURLConnection, OkHttp doesn't
    // reject non-standard HTTP methods.
    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    fun syncRoot(context: Context, accountId: String): File {
        val base = context.getExternalFilesDir(null) ?: context.filesDir
        return File(base, "sync/$accountId").apply { mkdirs() }
    }

    private fun stateKey(accountId: String) = "state_$accountId"

    fun loadState(context: Context, accountId: String): MutableMap<String, FileState> {
        val prefs = context.getSharedPreferences(STATE_PREFS, Context.MODE_PRIVATE)
        val json = prefs.getString(stateKey(accountId), null) ?: return mutableMapOf()
        val obj = JSONObject(json)
        val result = mutableMapOf<String, FileState>()
        for (fileId in obj.keys()) {
            val entry = obj.getJSONObject(fileId)
            result[fileId] = FileState(
                relPath = entry.getString("relPath"),
                etag = entry.getString("etag"),
                lastModified = entry.getLong("lastModified"),
                size = entry.getLong("size"),
                localMTime = entry.getLong("localMTime"),
            )
        }
        return result
    }

    fun saveState(context: Context, accountId: String, state: Map<String, FileState>) {
        val obj = JSONObject()
        for ((fileId, s) in state) {
            obj.put(
                fileId,
                JSONObject().apply {
                    put("relPath", s.relPath)
                    put("etag", s.etag)
                    put("lastModified", s.lastModified)
                    put("size", s.size)
                    put("localMTime", s.localMTime)
                },
            )
        }
        val prefs = context.getSharedPreferences(STATE_PREFS, Context.MODE_PRIVATE)
        prefs.edit().putString(stateKey(accountId), obj.toString()).apply()
    }

    /** Depth-1 PROPFIND of [remotePath], returning its direct children only. */
    fun propfindChildren(
        serverUrl: String,
        username: String,
        authHeader: String,
        remotePath: String,
    ): List<RemoteEntry> = propfind(serverUrl, username, authHeader, remotePath, depth = "1", skipSelf = true)

    /** Depth-0 PROPFIND of [remotePath] itself (e.g. to refresh its etag after a PUT/GET). */
    fun propfindSelf(
        serverUrl: String,
        username: String,
        authHeader: String,
        remotePath: String,
    ): RemoteEntry? = propfind(serverUrl, username, authHeader, remotePath, depth = "0", skipSelf = false).firstOrNull()

    private fun propfind(
        serverUrl: String,
        username: String,
        authHeader: String,
        remotePath: String,
        depth: String,
        skipSelf: Boolean,
    ): List<RemoteEntry> {
        var cleanPath = remotePath.trim()
        if (!cleanPath.startsWith("/")) cleanPath = "/$cleanPath"
        if (depth == "1" && !cleanPath.endsWith("/")) cleanPath = "$cleanPath/"
        val encodedPath = cleanPath.split("/").joinToString("/") { Uri.encode(it) }
        val cleanServer = serverUrl.trimEnd('/')
        val url = "$cleanServer/remote.php/dav/files/$username$encodedPath"

        val body = """<?xml version="1.0" encoding="utf-8" ?>
<d:propfind xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns">
  <d:prop>
    <d:getlastmodified/>
    <d:getcontentlength/>
    <d:resourcetype/>
    <d:getetag/>
    <oc:fileid/>
  </d:prop>
</d:propfind>"""
        val request = Request.Builder()
            .url(url)
            .method("PROPFIND", body.toRequestBody("application/xml".toMediaType()))
            .header("Authorization", authHeader)
            .header("Depth", depth)
            .build()

        return try {
            httpClient.newCall(request).execute().use { response ->
                Log.d(TAG, "PROPFIND $url -> ${response.code}")
                if (!response.isSuccessful) {
                    Log.w(TAG, "PROPFIND $url failed: ${response.code} ${response.body?.string()}")
                    return emptyList()
                }

                val doc = DocumentBuilderFactory.newInstance()
                    .apply { isNamespaceAware = true }
                    .newDocumentBuilder()
                    .parse(response.body!!.byteStream())

                parsePropfindResponse(doc, username, cleanPath, skipSelf)
            }
        } catch (e: Exception) {
            Log.e(TAG, "PROPFIND $url threw", e)
            emptyList()
        }
    }

    private fun parsePropfindResponse(
        doc: org.w3c.dom.Document,
        username: String,
        cleanPath: String,
        skipSelf: Boolean,
    ): List<RemoteEntry> {
            val marker = "/remote.php/dav/files/$username"
            val selfPath = cleanPath.trimEnd('/')
            val responses = doc.getElementsByTagNameNS("DAV:", "response")
            val entries = mutableListOf<RemoteEntry>()
            for (i in 0 until responses.length) {
                val responseEl = responses.item(i) as? Element ?: continue
                val hrefRaw = responseEl.getElementsByTagNameNS("DAV:", "href")
                    .item(0)?.textContent ?: continue
                val decodedHref = Uri.decode(hrefRaw)
                val idx = decodedHref.indexOf(marker)
                val hrefPath = if (idx >= 0) decodedHref.substring(idx + marker.length) else decodedHref
                val hrefPathNorm = (if (hrefPath.isEmpty()) "/" else hrefPath).trimEnd('/')
                if (skipSelf && hrefPathNorm == selfPath) continue // self entry, not a child

                val propEl = responseEl.getElementsByTagNameNS("DAV:", "prop").item(0) as? Element
                    ?: continue
                val resourceTypeEl =
                    propEl.getElementsByTagNameNS("DAV:", "resourcetype").item(0) as? Element
                val isFolder =
                    (resourceTypeEl?.getElementsByTagNameNS("DAV:", "collection")?.length ?: 0) > 0
                val etag = propEl.getElementsByTagNameNS("DAV:", "getetag")
                    .item(0)?.textContent?.trim('"') ?: ""
                val lastModStr =
                    propEl.getElementsByTagNameNS("DAV:", "getlastmodified").item(0)?.textContent
                val sizeStr =
                    propEl.getElementsByTagNameNS("DAV:", "getcontentlength").item(0)?.textContent
                val fileId = propEl.getElementsByTagNameNS("http://owncloud.org/ns", "fileid")
                    .item(0)?.textContent ?: hrefPathNorm

                entries.add(
                    RemoteEntry(
                        path = hrefPathNorm,
                        fileId = fileId,
                        etag = etag,
                        lastModified = lastModStr?.let { runCatching { rfc1123.parse(it)?.time }.getOrNull() } ?: 0L,
                        size = sizeStr?.toLongOrNull() ?: 0L,
                        isFolder = isFolder,
                    ),
                )
            }
            Log.d(TAG, "PROPFIND $cleanPath -> ${entries.size} entries")
            return entries
    }

    /** Recursively walks [rootPath] (Depth-1 PROPFINDs, breadth-first) into a flat manifest. */
    fun walkRemoteTree(
        serverUrl: String,
        username: String,
        authHeader: String,
        rootPath: String,
    ): List<RemoteEntry> {
        val result = mutableListOf<RemoteEntry>()
        val queue = ArrayDeque<String>()
        queue.add(rootPath)
        while (queue.isNotEmpty()) {
            val current = queue.removeFirst()
            val children = propfindChildren(serverUrl, username, authHeader, current)
            for (child in children) {
                result.add(child)
                if (child.isFolder) queue.add(child.path)
            }
        }
        return result
    }

    fun downloadFile(
        serverUrl: String,
        username: String,
        authHeader: String,
        remotePath: String,
        destination: File,
    ): Boolean {
        val encodedPath = remotePath.split("/").joinToString("/") { Uri.encode(it) }
        val url = URL("${serverUrl.trimEnd('/')}/remote.php/dav/files/$username$encodedPath")
        val connection = url.openConnection() as HttpURLConnection
        return try {
            connection.requestMethod = "GET"
            connection.setRequestProperty("Authorization", authHeader)
            connection.connectTimeout = 15000
            connection.readTimeout = 30000
            connection.connect()
            val code = connection.responseCode
            if (code !in 200..299) {
                Log.w(TAG, "GET $url failed: $code")
                return false
            }

            destination.parentFile?.mkdirs()
            connection.inputStream.use { input ->
                destination.outputStream().use { output -> input.copyTo(output) }
            }
            Log.d(TAG, "GET $url -> saved to ${destination.absolutePath} (${destination.length()} bytes)")
            true
        } catch (e: Exception) {
            Log.e(TAG, "GET $url threw", e)
            false
        } finally {
            connection.disconnect()
        }
    }

    fun uploadFile(
        serverUrl: String,
        username: String,
        authHeader: String,
        remotePath: String,
        source: File,
    ): Boolean {
        val encodedPath = remotePath.split("/").joinToString("/") { Uri.encode(it) }
        val url = URL("${serverUrl.trimEnd('/')}/remote.php/dav/files/$username$encodedPath")
        val connection = url.openConnection() as HttpURLConnection
        return try {
            connection.requestMethod = "PUT"
            connection.setRequestProperty("Authorization", authHeader)
            connection.setFixedLengthStreamingMode(source.length())
            connection.doOutput = true
            connection.connectTimeout = 15000
            connection.readTimeout = 60000
            connection.connect()
            source.inputStream().use { input ->
                connection.outputStream.use { output -> input.copyTo(output) }
            }
            connection.responseCode in 200..299
        } catch (e: Exception) {
            false
        } finally {
            connection.disconnect()
        }
    }

    /**
     * Diffs one synced folder's remote manifest against the persisted
     * state, returning what to do for each item - callers own actually
     * doing the GET/PUT/delete and updating state afterward, so this stays
     * pure/testable-in-principle. Also returns entries no longer present
     * remotely (deleted server-side, relative to the [priorFolderRelPaths]
     * this folder previously produced) as [SyncAction.Delete].
     */
    fun diffFolder(
        entries: List<RemoteEntry>,
        state: Map<String, FileState>,
        priorFolderFileIds: Set<String>,
        syncRoot: File,
    ): List<SyncAction> {
        val actions = mutableListOf<SyncAction>()
        val seenFileIds = mutableSetOf<String>()

        for (entry in entries) {
            if (entry.isFolder) continue
            seenFileIds.add(entry.fileId)
            val relPath = entry.path.removePrefix("/")
            val localFile = File(syncRoot, relPath)
            val prior = state[entry.fileId]

            if (prior == null) {
                // First time this folder's been walked with sync enabled -
                // nothing locally recorded yet to protect, so just pull it.
                actions.add(SyncAction.Download(entry))
                continue
            }

            val serverChanged = entry.etag != prior.etag
            val localExists = localFile.exists()
            val localChanged = localExists &&
                (localFile.lastModified() != prior.localMTime || localFile.length() != prior.size)

            when {
                !localExists && !serverChanged -> {
                    // User deleted the local mirror copy themselves and the
                    // server hasn't changed - respect that deletion rather
                    // than silently re-creating it.
                    actions.add(SyncAction.Delete(relPath, entry.fileId))
                }
                serverChanged && localChanged -> actions.add(SyncAction.Conflict(entry, relPath))
                serverChanged -> actions.add(SyncAction.Download(entry))
                localChanged -> actions.add(SyncAction.Upload(relPath, entry.fileId))
                else -> {} // unchanged, nothing to do
            }
        }

        // Anything this folder had state for last time but that didn't show
        // up in this walk at all was deleted server-side.
        for (fileId in priorFolderFileIds) {
            if (fileId !in seenFileIds) {
                val prior = state[fileId] ?: continue
                actions.add(SyncAction.Delete(prior.relPath, fileId))
            }
        }

        Log.d(
            TAG,
            "diffFolder: ${entries.size} entries -> " +
                "${actions.count { it is SyncAction.Download }} downloads, " +
                "${actions.count { it is SyncAction.Upload }} uploads, " +
                "${actions.count { it is SyncAction.Delete }} deletes, " +
                "${actions.count { it is SyncAction.Conflict }} conflicts",
        )
        return actions
    }

    fun folderIsSyncedUnder(itemPath: String, syncedFolders: List<String>): String? {
        val normalizedItem = itemPath.trimEnd('/')
        for (folder in syncedFolders) {
            val normalizedFolder = folder.trimEnd('/')
            if (normalizedItem == normalizedFolder || normalizedItem.startsWith("$normalizedFolder/")) {
                return folder
            }
        }
        return null
    }
}
