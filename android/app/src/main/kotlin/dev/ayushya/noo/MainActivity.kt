package dev.ayushya.noo

import android.Manifest
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

// FlutterFragmentActivity (not the default FlutterActivity) is required by
// local_auth's Android implementation, which hosts its biometric/device
// credential prompt via a Fragment.
//
// Also hand-rolls "Share to Noo" intent handling instead of using the
// receive_sharing_intent plugin: that plugin resolves a shared content:// URI
// by synchronously copying the *entire* file into the app's cache dir on the
// main thread, during activity startup, before Flutter has even drawn its
// first frame - fine for a photo, but for a large video/archive it blocks
// long enough that Android decides this newly-launched activity failed to
// render and kills it (silently back to the home screen - no crash, no
// Dart-side error, since Dart never got a chance to run). Other file-manager
// apps show their destination picker instantly regardless of file size
// because they defer touching the file's actual bytes until the user picks
// a destination - `getInitialShare`/`onNewShare` only ever query cheap Uri
// metadata (name/size/mime, not content). The actual copy+upload then runs
// in ShareUploadService (see its own doc comment), not here, so it survives
// the app being closed right after the user confirms a destination.
class MainActivity : FlutterFragmentActivity() {
    private val shareIntentChannelName = "dev.ayushya.noo/share_intent"
    private val newShareChannelName = "dev.ayushya.noo/share_intent/new"
    private val uploadServiceChannelName = "dev.ayushya.noo/upload_service"
    private val downloadServiceChannelName = "dev.ayushya.noo/download_service"
    private val pickIntentChannelName = "dev.ayushya.noo/pick_intent"
    private val newPickChannelName = "dev.ayushya.noo/pick_intent/new"
    private val notificationPermissionRequestCode = 4202
    // Lazy, not a field initializer - `packageName` reads through the
    // Activity's base Context, which isn't attached yet while this class's
    // fields are being constructed (crashes with an NPE if evaluated then).
    private val pickerFileProviderAuthority by lazy { "$packageName.picker.fileprovider" }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var newShareSink: EventChannel.EventSink? = null
    private var newPickSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareIntentChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialShare" -> result.success(extractShareMetadata(intent))
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, newShareChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    newShareSink = events
                }
                override fun onCancel(arguments: Any?) {
                    newShareSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, uploadServiceChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startUpload" -> {
                        startUploadService(call, result)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, downloadServiceChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startDownload" -> {
                        startDownloadService(call, result)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, pickIntentChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getPickRequest" -> result.success(extractPickRequest(intent))
                    "finishPick" -> finishPick(call, result)
                    "cancelPick" -> cancelPick(result)
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, newPickChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    newPickSink = events
                }
                override fun onCancel(arguments: Any?) {
                    newPickSink = null
                }
            })
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val shared = extractShareMetadata(intent)
        if (shared.isNotEmpty()) {
            mainHandler.post { newShareSink?.success(shared) }
        }
        val pickRequest = extractPickRequest(intent)
        if (pickRequest != null) {
            mainHandler.post { newPickSink?.success(pickRequest) }
        }
    }

    /// Cheap Uri metadata only (display name / size / mime type) via a
    /// single ContentResolver query - never reads the file's actual bytes,
    /// so this is fast regardless of how large the shared file is.
    private fun extractShareMetadata(intent: Intent): List<Map<String, Any?>> {
        val uris: List<Uri> = when (intent.action) {
            Intent.ACTION_SEND -> listOfNotNull(intentStreamUri(intent))
            Intent.ACTION_SEND_MULTIPLE -> intentStreamUris(intent)
            else -> emptyList()
        }
        return uris.map { uriMetadata(it) }
    }

    @Suppress("DEPRECATION")
    private fun intentStreamUri(intent: Intent): Uri? {
        return if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }
    }

    @Suppress("DEPRECATION")
    private fun intentStreamUris(intent: Intent): List<Uri> {
        val list = if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
        }
        return list ?: emptyList()
    }

    private fun uriMetadata(uri: Uri): Map<String, Any?> {
        var name = uri.lastPathSegment ?: "shared_file"
        var size: Long? = null
        try {
            contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (nameIdx >= 0) cursor.getString(nameIdx)?.let { name = it }
                    val sizeIdx = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (sizeIdx >= 0 && !cursor.isNull(sizeIdx)) size = cursor.getLong(sizeIdx)
                }
            }
        } catch (_: Exception) {
            // Fall back to the Uri-derived name / unknown size below.
        }
        val mimeType = contentResolver.getType(uri)
        return mapOf("uri" to uri.toString(), "name" to name, "mimeType" to mimeType, "size" to size)
    }

    /// Starts ShareUploadService with everything it needs to run entirely on
    /// its own (see its doc comment) - the Intent extras are the full
    /// contract between this call and that service, kept in sync manually
    /// since they cross the Kotlin/Dart boundary as loosely-typed args.
    private fun startUploadService(call: MethodCall, result: MethodChannel.Result) {
        val filesJson = call.argument<String>("files")
        val serverUrl = call.argument<String>("serverUrl")
        val username = call.argument<String>("username")
        val authHeader = call.argument<String>("authHeader")
        val remoteFolder = call.argument<String>("remoteFolder")
        if (filesJson == null || serverUrl == null || username == null ||
            authHeader == null || remoteFolder == null
        ) {
            result.error("bad_args", "Missing required upload arguments", null)
            return
        }

        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            // Fire-and-forget: the service works fine even if this is denied,
            // it just won't be able to show progress/cancel in a notification.
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                notificationPermissionRequestCode,
            )
        }

        val serviceIntent = Intent(this, ShareUploadService::class.java).apply {
            putExtra(ShareUploadService.EXTRA_FILES, filesJson)
            putExtra(ShareUploadService.EXTRA_SERVER_URL, serverUrl)
            putExtra(ShareUploadService.EXTRA_USERNAME, username)
            putExtra(ShareUploadService.EXTRA_AUTH_HEADER, authHeader)
            putExtra(ShareUploadService.EXTRA_REMOTE_FOLDER, remoteFolder)
        }
        ContextCompat.startForegroundService(this, serviceIntent)
        result.success(null)
    }

    /// Starts DownloadService with everything it needs to run entirely on
    /// its own (see its doc comment) - same contract shape as
    /// [startUploadService], kept in sync manually for the same reason.
    private fun startDownloadService(call: MethodCall, result: MethodChannel.Result) {
        val filesJson = call.argument<String>("files")
        val serverUrl = call.argument<String>("serverUrl")
        val username = call.argument<String>("username")
        val authHeader = call.argument<String>("authHeader")
        if (filesJson == null || serverUrl == null || username == null || authHeader == null) {
            result.error("bad_args", "Missing required download arguments", null)
            return
        }

        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            // Fire-and-forget: the service works fine even if this is denied,
            // it just won't be able to show progress/cancel in a notification.
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                notificationPermissionRequestCode,
            )
        }

        val serviceIntent = Intent(this, DownloadService::class.java).apply {
            putExtra(DownloadService.EXTRA_FILES, filesJson)
            putExtra(DownloadService.EXTRA_SERVER_URL, serverUrl)
            putExtra(DownloadService.EXTRA_USERNAME, username)
            putExtra(DownloadService.EXTRA_AUTH_HEADER, authHeader)
        }
        ContextCompat.startForegroundService(this, serviceIntent)
        result.success(null)
    }

    /// Non-null only when this Activity was launched (or re-delivered a new
    /// Intent) as another app's GET_CONTENT picker - the mimeType filter and
    /// multi-select flag the caller asked for, plus a best-effort display
    /// name for the calling app to show in the "picking mode" banner.
    private fun extractPickRequest(intent: Intent): Map<String, Any?>? {
        if (intent.action != Intent.ACTION_GET_CONTENT) return null
        val mimeType = intent.type ?: "*/*"
        val allowMultiple = intent.getBooleanExtra(Intent.EXTRA_ALLOW_MULTIPLE, false)
        val callerPackage = callingPackage
        val callerLabel = callerPackage?.let {
            try {
                val appInfo = packageManager.getApplicationInfo(it, 0)
                packageManager.getApplicationLabel(appInfo).toString()
            } catch (_: PackageManager.NameNotFoundException) {
                it
            }
        }
        return mapOf(
            "mimeType" to mimeType,
            "allowMultiple" to allowMultiple,
            "callerLabel" to callerLabel,
        )
    }

    /// Hands the already-downloaded local files (see PickIntentService/
    /// ServerProvider.confirmPick - this Activity never touches the
    /// Nextcloud server itself) back to the caller as content:// Uris
    /// through this app's own FileProvider, then closes the picker.
    private fun finishPick(call: MethodCall, result: MethodChannel.Result) {
        val paths = call.argument<List<String>>("paths")
        val mimeTypes = call.argument<List<String>>("mimeTypes") ?: emptyList()
        if (paths.isNullOrEmpty()) {
            result.error("no_files", "No files to return to the caller", null)
            return
        }

        val uris = paths.map { path ->
            FileProvider.getUriForFile(this, pickerFileProviderAuthority, File(path))
        }
        val resultIntent = Intent().apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        // `Intent.setData()` and `.setType()` each silently null out the
        // other field if called separately (Android framework behavior) -
        // `setDataAndType` is the only way to have both survive on the same
        // Intent, which every GET_CONTENT caller expects for `data`.
        val firstMimeType = mimeTypes.getOrNull(0) ?: "*/*"
        if (uris.size == 1) {
            resultIntent.setDataAndType(uris[0], firstMimeType)
        } else {
            val clipMimeTypes = mimeTypes.ifEmpty { listOf("*/*") }.toTypedArray()
            val clipData = ClipData("Noo picked files", clipMimeTypes, ClipData.Item(uris[0]))
            for (i in 1 until uris.size) clipData.addItem(ClipData.Item(uris[i]))
            resultIntent.clipData = clipData
            // Some callers only read `data` even for a multi-item pick, so
            // this still points at the first file as a fallback.
            resultIntent.setDataAndType(uris[0], firstMimeType)
        }
        setResult(RESULT_OK, resultIntent)
        result.success(null)
        finish()
    }

    private fun cancelPick(result: MethodChannel.Result) {
        setResult(RESULT_CANCELED)
        result.success(null)
        finish()
    }
}
