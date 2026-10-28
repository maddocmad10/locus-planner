package com.example.locusplanner.locus_planner

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject

/** One notification to show at [at], in epoch milliseconds. */
data class Reminder(
    val id: String,
    val at: Long,
    val title: String,
    val body: String,
)

/**
 * Event reminders that work while the app is closed.
 *
 * The Dart side computes the upcoming reminders (it knows how events recur)
 * and hands over the whole list with [replaceAll]. The list is stored here and
 * a single alarm is kept armed for the earliest entry; when it fires, every
 * due entry is shown and the alarm moves on to the next one. One alarm at a
 * time keeps well inside Android's limits on alarms per app, and because the
 * list is stored, [fireDue] can rebuild everything after a reboot without the
 * Flutter engine.
 */
object Reminders {
    const val CHANNEL_ID = "event_reminders"

    private const val PREFS = "locus_reminders"
    private const val KEY_ITEMS = "items"
    private const val ALARM_REQUEST_CODE = 7301

    /** Same rule as the desktop app: a reminder over 15 minutes late is skipped. */
    private const val MAX_LATENESS_MS = 15 * 60 * 1000L

    fun load(context: Context): List<Reminder> {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_ITEMS, null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).map { index ->
                val item = array.getJSONObject(index)
                Reminder(
                    id = item.getString("id"),
                    at = item.getLong("at"),
                    title = item.getString("title"),
                    body = item.getString("body"),
                )
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun save(context: Context, items: List<Reminder>) {
        val array = JSONArray()
        for (item in items) {
            array.put(
                JSONObject()
                    .put("id", item.id)
                    .put("at", item.at)
                    .put("title", item.title)
                    .put("body", item.body),
            )
        }
        // commit(), not apply(): this can run in a receiver whose process may
        // be stopped right after it returns.
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_ITEMS, array.toString())
            .commit()
    }

    /** Replaces every pending reminder with [items] and re-arms the alarm. */
    fun replaceAll(context: Context, items: List<Reminder>) {
        // A reminder that is due but whose alarm was late must not be lost
        // just because the app was opened and sent a fresh list that no longer
        // contains it.
        fireDue(context)
        val now = System.currentTimeMillis()
        val kept = items.filter { now - it.at <= MAX_LATENESS_MS }.sortedBy { it.at }
        save(context, kept)
        schedule(context)
    }

    fun cancelAll(context: Context) {
        save(context, emptyList())
        schedule(context)
    }

    /**
     * Shows every reminder that is due (skipping any more than 15 minutes
     * late), removes them from the list and arms the alarm for the next one.
     * Also the way back after a reboot or an app update, when alarms are gone.
     */
    fun fireDue(context: Context) {
        val now = System.currentTimeMillis()
        val (due, upcoming) = load(context).partition { it.at <= now }
        if (due.isNotEmpty()) save(context, upcoming)
        for (reminder in due) {
            if (now - reminder.at <= MAX_LATENESS_MS) show(context, reminder)
        }
        schedule(context)
    }

    /** Arms one alarm for the earliest stored reminder, or none if empty. */
    private fun schedule(context: Context) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pending = alarmIntent(context)
        val next = load(context).minByOrNull { it.at }
        if (next == null) {
            alarms.cancel(pending)
            return
        }
        try {
            if (canScheduleExact(alarms)) {
                alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.at, pending)
            } else {
                alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.at, pending)
            }
        } catch (e: SecurityException) {
            // Exact alarms were revoked between the check and the call.
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.at, pending)
        }
    }

    /** Android 12+ makes exact alarms a permission the user can withdraw. */
    fun canScheduleExact(alarms: AlarmManager): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarms.canScheduleExactAlarms()

    private fun alarmIntent(context: Context): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            ALARM_REQUEST_CODE,
            Intent(context, ReminderReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun show(context: Context, reminder: Reminder) {
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Event reminders",
                NotificationManager.IMPORTANCE_HIGH,
            )
            channel.description = "Alerts shortly before your planner events start."
            manager.createNotificationChannel(channel)
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context).setPriority(Notification.PRIORITY_HIGH)
        }
        builder
            .setSmallIcon(R.drawable.ic_stat_reminder)
            .setContentTitle(reminder.title)
            .setContentText(reminder.body)
            .setCategory(Notification.CATEGORY_REMINDER)
            .setAutoCancel(true)
        // Tapping the notification opens the app.
        context.packageManager.getLaunchIntentForPackage(context.packageName)?.let { launch ->
            builder.setContentIntent(
                PendingIntent.getActivity(
                    context,
                    0,
                    launch,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )
        }
        // Without the notification permission (Android 13+) this is a no-op.
        manager.notify(reminder.id.hashCode(), builder.build())
    }
}
