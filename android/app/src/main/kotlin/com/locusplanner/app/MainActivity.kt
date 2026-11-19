package com.locusplanner.app

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.provider.Settings
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

class MainActivity : FlutterActivity() {
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var reminderChannel: MethodChannel? = null
    private var shareIntakeChannel: MethodChannel? = null
    private val pendingShares = mutableListOf<Map<String, String>>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        reminderChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            REMINDER_CHANNEL,
        )
        reminderChannel
            ?.setMethodCallHandler { call, result -> handleReminderCall(call, result) }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PRIVACY_CHANNEL)
            .setMethodCallHandler { call, result -> handlePrivacyCall(call, result) }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL)
            .setMethodCallHandler { call, result -> handleShareCall(call, result) }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CLIPBOARD_CHANNEL)
            .setMethodCallHandler { call, result -> handleClipboardCall(call, result) }
        shareIntakeChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SHARE_INTAKE_CHANNEL,
        )
        shareIntakeChannel?.setMethodCallHandler { call, result ->
            if (call.method == "takeSharedFiles") {
                val copy = pendingShares.toList()
                pendingShares.clear()
                result.success(copy)
            } else {
                result.notImplemented()
            }
        }
        handleIncomingShare(intent)
    }

    /// Copies ACTION_SEND content into the app cache and queues it for Dart.
    /// Only the copied app-private path is exposed; the original URI is not
    /// retained.
    private fun handleIncomingShare(intent: Intent?) {
        if (intent == null) return
        if (intent.action != Intent.ACTION_SEND &&
            intent.action != Intent.ACTION_SEND_MULTIPLE
        ) {
            return
        }
        val uris = mutableListOf<android.net.Uri>()
        val clip = intent.clipData
        if (clip != null) {
            for (index in 0 until clip.itemCount) {
                clip.getItemAt(index).uri?.let { uris.add(it) }
            }
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra<android.net.Uri>(Intent.EXTRA_STREAM)?.let {
                uris.add(it)
            }
        }
        val directory = File(cacheDir, "shared")
        directory.mkdirs()
        for (uri in uris) {
            try {
                val mime = contentResolver.getType(uri)
                    ?: intent.type
                    ?: "application/octet-stream"
                val name = queryDisplayName(uri) ?: "shared-file"
                val safe = name
                    .replace(Regex("[^A-Za-z0-9._-]"), "_")
                    .take(80)
                    .ifBlank { "shared" }
                val target = File(directory, "${UUID.randomUUID()}-$safe")
                contentResolver.openInputStream(uri)?.use { input ->
                    target.outputStream().use { output -> input.copyTo(output) }
                } ?: continue
                pendingShares.add(
                    mapOf(
                        "path" to target.absolutePath,
                        "name" to name,
                        "mimeType" to mime,
                    ),
                )
            } catch (_: Exception) {
                // One unreadable shared item must not drop the others.
            }
        }
        if (pendingShares.isNotEmpty()) {
            shareIntakeChannel?.invokeMethod("sharedFiles", pendingShares.toList())
        }
    }

    private fun queryDisplayName(uri: android.net.Uri): String? {
        return try {
            contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        } catch (_: Exception) {
            null
        }
    }

    /// Returns image bytes from a clipboard content URI, or null when the
    /// clipboard has no image. Text and arbitrary file URIs are ignored.
    private fun handleClipboardCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "readImage") {
            result.notImplemented()
            return
        }
        try {
            val manager = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            val clip = manager.primaryClip
            val description = manager.primaryClipDescription
            if (clip == null) {
                result.success(null)
                return
            }
            for (index in 0 until clip.itemCount) {
                val uri = clip.getItemAt(index).uri ?: continue
                val mime = description?.getMimeType(index) ?: ""
                if (!mime.startsWith("image/")) continue
                val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                if (bytes != null) {
                    result.success(bytes)
                    return
                }
            }
            result.success(null)
        } catch (e: Exception) {
            result.error("clipboard_failed", e.message, null)
        }
    }

    /// Opens a decrypted attachment copy through the system picker. The
    /// sealed blob is never exposed; only the per-session temp file is.
    private fun handleShareCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "share") {
            result.notImplemented()
            return
        }
        val path = call.argument<String>("path")
        val mime = call.argument<String>("mimeType") ?: "application/octet-stream"
        if (path.isNullOrBlank()) {
            result.error("invalid_path", "Attachment path is missing", null)
            return
        }
        try {
            val file = java.io.File(path)
            if (!file.exists()) {
                result.error("missing_file", "Attachment file is missing", null)
                return
            }
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                file,
            )
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = mime
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(intent, "Open attachment"))
            result.success(null)
        } catch (e: Exception) {
            result.error("share_failed", e.message, null)
        }
    }

    /// Hides private content from screenshots and the recent-apps thumbnail
    /// while the app lock is on.
    private fun handlePrivacyCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setSecure" -> {
                val secure = call.argument<Boolean>("secure") ?: false
                if (secure) {
                    window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                } else {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                }
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun handleReminderCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "launchTab" -> result.success(intent?.getStringExtra("locus.open_tab"))

            "replaceAll" -> {
                try {
                    val raw = call.argument<List<Map<String, Any?>>>("reminders") ?: emptyList()
                    val items = raw.map {
                        Reminder(
                            id = it["id"] as String,
                            kind = (it["kind"] as String?) ?: "event",
                            at = (it["at"] as Number).toLong(),
                            title = it["title"] as String,
                            body = it["body"] as String,
                        )
                    }
                    Reminders.replaceAll(applicationContext, items)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("reminders_failed", e.message, null)
                }
            }

            "cancelAll" -> {
                Reminders.cancelAll(applicationContext)
                result.success(null)
            }

            "stats" -> result.success(Reminders.stats(applicationContext))

            "capabilities" -> {
                val alarms = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                result.success(
                    mapOf(
                        "notificationsAllowed" to notificationsAllowed(),
                        "exactAlarmsAllowed" to Reminders.systemAllowsExact(alarms),
                        "exactAlarmsEnabled" to Reminders.exactRemindersEnabled(this),
                    ),
                )
            }

            "setExactAlarmsEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: true
                Reminders.setExactRemindersEnabled(applicationContext, enabled)
                result.success(null)
            }

            "requestNotificationPermission" -> requestNotificationPermission(result)

            "openExactAlarmSettings" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    openSettings(
                        Intent(
                            Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                            Uri.parse("package:$packageName"),
                        ),
                    )
                }
                result.success(null)
            }

            "openNotificationSettings" -> {
                val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                        .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                } else {
                    Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.parse("package:$packageName"),
                    )
                }
                openSettings(intent)
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun notificationsAllowed(): Boolean {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return manager.areNotificationsEnabled()
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (notificationsAllowed()) {
            result.success(true)
        } else if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            // Before Android 13 the app cannot ask; the user turned them off.
            result.success(false)
        } else {
            // A second request replaces the first, which is answered "no".
            pendingPermissionResult?.success(false)
            pendingPermissionResult = result
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                REQUEST_NOTIFICATIONS,
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_NOTIFICATIONS) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        reminderChannel?.invokeMethod(
            "openTab",
            intent.getStringExtra("locus.open_tab"),
        )
        handleIncomingShare(intent)
    }

    private fun openSettings(intent: Intent) {
        try {
            startActivity(intent)
        } catch (e: ActivityNotFoundException) {
            // This device has no such settings screen; nothing more to do.
        }
    }

    private companion object {
        const val REMINDER_CHANNEL = "locus_planner/reminders"
        const val PRIVACY_CHANNEL = "locus_planner/privacy"
        const val SHARE_CHANNEL = "locus_planner/share"
        const val CLIPBOARD_CHANNEL = "locus_planner/clipboard"
        const val SHARE_INTAKE_CHANNEL = "locus_planner/share_intake"
        const val REQUEST_NOTIFICATIONS = 4711
    }
}
