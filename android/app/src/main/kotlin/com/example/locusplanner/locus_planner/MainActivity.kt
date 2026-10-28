package com.example.locusplanner.locus_planner

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, REMINDER_CHANNEL)
            .setMethodCallHandler { call, result -> handleReminderCall(call, result) }
    }

    private fun handleReminderCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "replaceAll" -> {
                try {
                    val raw = call.argument<List<Map<String, Any?>>>("reminders") ?: emptyList()
                    val items = raw.map {
                        Reminder(
                            id = it["id"] as String,
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

            "capabilities" -> {
                val alarms = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                result.success(
                    mapOf(
                        "notificationsAllowed" to notificationsAllowed(),
                        "exactAlarmsAllowed" to Reminders.canScheduleExact(alarms),
                    ),
                )
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

    private fun openSettings(intent: Intent) {
        try {
            startActivity(intent)
        } catch (e: ActivityNotFoundException) {
            // This device has no such settings screen; nothing more to do.
        }
    }

    private companion object {
        const val REMINDER_CHANNEL = "locus_planner/reminders"
        const val REQUEST_NOTIFICATIONS = 4711
    }
}
