package com.locusplanner.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Runs when the reminder alarm goes off, even if the app is not running. */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Reminders.fireDue(context)
    }
}
