package com.example.locusplanner.locus_planner

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Alarms do not survive a reboot or an app update, so arm the next reminder
 * again from the stored list (and show any that fell due in the meantime).
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            Reminders.fireDue(context)
        }
    }
}
