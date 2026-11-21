package com.locusplanner.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Android home-screen widget for the next few local items.
 *
 * Flutter writes a small snapshot with HomeWidget; this provider only renders
 * it. The stored day and zone are checked on every render so a stale snapshot
 * is labelled instead of being mistaken for today's plan.
 */
class TodayWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        render(context, appWidgetManager, appWidgetIds, widgetData)
    }

    companion object {
        private const val PREFS = "HomeWidgetPreferences"

        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, TodayWidgetProvider::class.java),
            )
            if (ids.isEmpty()) return
            render(
                context,
                manager,
                ids,
                context.getSharedPreferences(PREFS, Context.MODE_PRIVATE),
            )
        }

        private fun render(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetIds: IntArray,
            widgetData: SharedPreferences,
        ) {
            val bodyText = widgetData.getString(
                "today_body",
                "Open Locus to plan your day.",
            ) ?: "Open Locus to plan your day."
            val snapshotDay = widgetData.getString("snapshot_day", null)
            val storedZone = widgetData.getString("zone_id", null)
            val snapshotVersion = widgetData.getInt("snapshot_version", 0)
            val generatedAt = widgetData.getLong("snapshot_generated_at_ms", 0L)
            val now = System.currentTimeMillis()
            val zone = TimeZone.getDefault()
            val currentZone = "${zone.id}:${zone.getOffset(now)}"
            val currentDay = SimpleDateFormat("yyyy-MM-dd", Locale.US)
                .format(Date(now))
            val stale = snapshotVersion != 2 ||
                snapshotDay == null ||
                storedZone == null ||
                generatedAt == 0L ||
                snapshotDay != currentDay ||
                storedZone != currentZone

            val title = widgetData.getString("today_title", "Locus Planner")
                ?: "Locus Planner"
            val body = if (stale) {
                val snapshot = snapshotDay ?: "unknown"
                "Open to refresh\nSnapshot: $snapshot\n$bodyText"
            } else {
                bodyText
            }
            val actionLabel = if (stale) "Open to refresh" else "Add"

            val todayIntent = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
                ?.apply { putExtra("locus.open_tab", "today") }
            val addIntent = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
                ?.apply {
                    putExtra("locus.open_tab", "quick_capture")
                    putExtra("locus.quick_capture", true)
                }
            val openPending = todayIntent?.let {
                PendingIntent.getActivity(
                    context,
                    0,
                    it,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
            }
            val addPending = addIntent?.let {
                PendingIntent.getActivity(
                    context,
                    1,
                    it,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
            }

            for (appWidgetId in appWidgetIds) {
                val views = RemoteViews(context.packageName, R.layout.today_widget)
                views.setTextViewText(R.id.widget_title, title)
                views.setTextViewText(R.id.widget_body, body)
                views.setTextViewText(R.id.widget_action, actionLabel)
                if (openPending != null) {
                    views.setOnClickPendingIntent(R.id.widget_root, openPending)
                }
                if (addPending != null) {
                    views.setOnClickPendingIntent(R.id.widget_action, addPending)
                }
                appWidgetManager.updateAppWidget(appWidgetId, views)
            }
        }
    }
}
