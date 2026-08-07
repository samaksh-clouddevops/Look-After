package com.lookafter.app.execution

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.util.Log
import com.lookafter.core.models.ExecutionBlockSnapshot
import com.lookafter.core.models.ExecutionSurfaceMode

/**
 * Programmatic Do Not Disturb control for Anchored focus windows.
 * Mirrors iOS Focus Filter activation during strict execution blocks.
 *
 * Requires [NotificationManager.isNotificationPolicyAccessGranted].
 * Without it, [applyFocusState] is a no-op (safe on devices that deny access).
 */
class SystemFocusController(
    context: Context,
) {
    private val appContext = context.applicationContext
    private val notificationManager =
        appContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    /** True when the user has granted Look After notification-policy access. */
    val isPolicyAccessGranted: Boolean
        get() = notificationManager.isNotificationPolicyAccessGranted

    /**
     * Apply / release DND based on the current execution snapshot.
     * - Anchored + eligible → PRIORITY (alarms/priority only)
     * - Anything else → ALL (restore normal interruptions)
     */
    fun applyFocusState(snapshot: ExecutionBlockSnapshot) {
        if (!isPolicyAccessGranted) {
            Log.d(TAG, "DND policy access not granted — skip")
            return
        }

        val target = when {
            snapshot.isFocusEligible &&
                snapshot.surfaceMode == ExecutionSurfaceMode.ANCHORED ->
                NotificationManager.INTERRUPTION_FILTER_PRIORITY
            else -> NotificationManager.INTERRUPTION_FILTER_ALL
        }

        val current = notificationManager.currentInterruptionFilter
        if (current == target) return

        try {
            notificationManager.setInterruptionFilter(target)
            Log.i(
                TAG,
                "Interruption filter → ${filterName(target)} " +
                    "(mode=${snapshot.surfaceMode}, task=${snapshot.taskId})",
            )
        } catch (t: SecurityException) {
            Log.w(TAG, "Failed to set interruption filter", t)
        }
    }

    /** Force restore to ALL (e.g. service teardown). */
    fun releaseFocus() {
        if (!isPolicyAccessGranted) return
        try {
            if (notificationManager.currentInterruptionFilter !=
                NotificationManager.INTERRUPTION_FILTER_ALL
            ) {
                notificationManager.setInterruptionFilter(
                    NotificationManager.INTERRUPTION_FILTER_ALL,
                )
                Log.i(TAG, "Interruption filter restored to ALL")
            }
        } catch (t: SecurityException) {
            Log.w(TAG, "Failed to release interruption filter", t)
        }
    }

    companion object {
        private const val TAG = "SystemFocus"

        fun isPolicyAccessGranted(context: Context): Boolean {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            return nm.isNotificationPolicyAccessGranted
        }

        /** System screen where the user grants DND policy access to Look After. */
        fun notificationPolicySettingsIntent(): Intent =
            Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }

        private fun filterName(filter: Int): String = when (filter) {
            NotificationManager.INTERRUPTION_FILTER_ALL -> "ALL"
            NotificationManager.INTERRUPTION_FILTER_PRIORITY -> "PRIORITY"
            NotificationManager.INTERRUPTION_FILTER_NONE -> "NONE"
            NotificationManager.INTERRUPTION_FILTER_ALARMS -> "ALARMS"
            else -> "UNKNOWN($filter)"
        }
    }
}
