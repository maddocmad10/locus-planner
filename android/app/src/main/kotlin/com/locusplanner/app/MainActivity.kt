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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL)
            .setMethodCallHandler { call, result -> handleWidgetCall(call, result) }
        shareIntakeChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SHARE_INTAKE_CHANNEL,
        )
        shareIntakeChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "takeSharedIntakes" -> result.success(ShareIntake.take(this))
                "completeIntake" -> {
                    val id = call.argument<String>("id")
                    if (id.isNullOrBlank()) {
                        result.error("invalid_intake", "Missing intake id", null)
                    } else {
                        ShareIntake.complete(this, id)
                        result.success(null)
                    }
                }
                "takeSharedFiles" -> {
                    // Backwards-compatible flattened view for older callers.
                    val files = ShareIntake.take(this).flatMap { intake ->
                        (intake["files"] as? List<*>)?.filterIsInstance<Map<*, *>>()
                            ?: emptyList()
                    }
                    result.success(files)
                }
                else -> result.notImplemented()
            }
        }
        ShareIntake.sweep(this)
        handleIncomingShare(intent)
    }

    /// Stages ACTION_SEND content under an intake id. The copy runs off the UI
    /// thread and the intake survives rotation or process death until Dart
    /// commits the task.
    private fun handleIncomingShare(intent: Intent?) {
        ShareIntake.handle(this, intent) { id ->
            shareIntakeChannel?.invokeMethod("sharedIntake", id)
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

            "launchTarget" -> result.success(openTarget(intent))

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
                            entityId = (it["entityId"] as String?) ?: "",
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

    private fun openTarget(intent: Intent?): Map<String, String>? {
        val kind = intent?.getStringExtra("locus.open_kind") ?: return null
        val id = intent.getStringExtra("locus.open_id") ?: return null
        if (id.isBlank() || (kind != "task" && kind != "event")) return null
        return mapOf("kind" to kind, "id" to id)
    }

    private fun handleWidgetCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "zoneToken" -> result.success(widgetZoneToken())
            "publishSnapshot" -> result.success(publishWidgetSnapshot(call))
            else -> result.notImplemented()
        }
    }

    /// Commits a whole widget snapshot in one preferences edit and only then
    /// redraws. The day and zone are checked here so a snapshot generated for
    /// another timezone (or a different civil day) never replaces a complete
    /// one. A late generation from an older update is dropped.
    private fun publishWidgetSnapshot(call: MethodCall): Map<String, Any?> {
        val generatedAt = call.argument<Number>("generatedAtMs")?.toLong()
        val generation = call.argument<Number>("generation")?.toLong()
        val title = call.argument<String>("title")
        val body = call.argument<String>("body")
        val eventCount = call.argument<Number>("eventCount")?.toInt()
        val taskCount = call.argument<Number>("taskCount")?.toInt()
        val habitCount = call.argument<Number>("habitCount")?.toInt()
        if (generatedAt == null ||
            generation == null ||
            title == null ||
            body == null ||
            eventCount == null ||
            taskCount == null ||
            habitCount == null ||
            eventCount < 0 ||
            taskCount < 0 ||
            habitCount < 0
        ) {
            return mapOf("ok" to false, "reason" to "invalid_snapshot")
        }

        val token = widgetZoneToken()
        val expected = call.argument<String>("expectedZoneToken")
        if (expected != null && expected != token) {
            // Let Dart refresh its zone token and retry once immediately.
            return mapOf(
                "ok" to false,
                "reason" to "zone_changed",
                "zoneToken" to token,
            )
        }

        val day = widgetDay(generatedAt)
        val providedDay = call.argument<String>("day")
        if (providedDay != null && providedDay != day) {
            return mapOf(
                "ok" to false,
                "reason" to "day_mismatch",
                "day" to day,
            )
        }

        val prefs = getSharedPreferences(
            "HomeWidgetPreferences",
            Context.MODE_PRIVATE,
        )
        val previousGeneration = prefs.getLong("snapshot_generation", 0L)
        if (generation <= previousGeneration) {
            return mapOf(
                "ok" to false,
                "reason" to "stale_generation",
                "generation" to previousGeneration,
            )
        }

        // One editor means the widget never renders a title from one snapshot
        // and counts from another. commit() is checked: on failure the previous
        // complete snapshot stays in place.
        val committed = prefs.edit()
            .putInt("snapshot_version", 2)
            .putString("snapshot_day", day)
            .putString("zone_id", token)
            .putLong("snapshot_generated_at_ms", generatedAt)
            .putLong("snapshot_generation", generation)
            .putString("today_title", title)
            .putString("today_body", body)
            .putInt("today_event_count", eventCount)
            .putInt("today_task_count", taskCount)
            .putInt("today_habit_count", habitCount)
            .commit()
        if (!committed) {
            return mapOf("ok" to false, "reason" to "commit_failed")
        }
        TodayWidgetProvider.refreshAll(applicationContext)
        return mapOf(
            "ok" to true,
            "generation" to generation,
            "zoneToken" to token,
            "day" to day,
        )
    }

    private fun widgetDay(timestampMs: Long): String {
        val zone = java.util.TimeZone.getDefault()
        return java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US)
            .apply { timeZone = zone }
            .format(java.util.Date(timestampMs))
    }

    private fun widgetZoneToken(): String {
        val zone = java.util.TimeZone.getDefault()
        return "${zone.id}:${zone.getOffset(System.currentTimeMillis())}"
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
        reminderChannel?.invokeMethod("openTarget", openTarget(intent))
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
        const val WIDGET_CHANNEL = "locus_planner/widget_snapshot"
        const val SHARE_INTAKE_CHANNEL = "locus_planner/share_intake"
        const val REQUEST_NOTIFICATIONS = 4711
    }
}
