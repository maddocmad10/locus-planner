package com.locusplanner.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Alarms do not survive a reboot or an app update, so arm the next reminder
 * again from the stored list (and show any that fell due in the meantime).
 * The widget is re-rendered so a date or zone change is labelled immediately.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> Reminders.fireDue(context)
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_DATE_CHANGED -> Unit
        }
        TodayWidgetProvider.refreshAll(context)
    }
}
