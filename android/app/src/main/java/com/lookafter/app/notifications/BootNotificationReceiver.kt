package com.lookafter.app.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Re-arms persisted notification alarms after device boot or app update.
 * Does not require the full Compose shell — only [NotificationPlanStore] + AlarmManager.
 */
class BootNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_LOCKED_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            return
        }
        Log.i(TAG, "Rescheduling notifications after $action")
        val pending = goAsync()
        try {
            LookAfterNotifier(context.applicationContext).reschedulePersisted()
        } catch (t: Throwable) {
            Log.w(TAG, "Failed to reschedule notifications", t)
        } finally {
            pending.finish()
        }
    }

    companion object {
        private const val TAG = "BootNotify"
    }
}
