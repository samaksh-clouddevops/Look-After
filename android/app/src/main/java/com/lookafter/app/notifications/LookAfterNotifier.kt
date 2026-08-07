package com.lookafter.app.notifications

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.lookafter.app.MainActivity
import com.lookafter.core.notifications.NotificationKind
import com.lookafter.core.notifications.PlannedNotification
import java.time.Instant

/**
 * Schedules [PlannedNotification]s via AlarmManager and posts them when due.
 * Pure planning stays in lookafter-core [com.lookafter.core.notifications.NotificationPolicy].
 */
class LookAfterNotifier(private val context: Context) {

    fun ensureChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val mgr = context.getSystemService(NotificationManager::class.java) ?: return
        val channels = listOf(
            NotificationChannel(CHANNEL_CARE, "Care & meds", NotificationManager.IMPORTANCE_HIGH),
            NotificationChannel(CHANNEL_SCHEDULE, "Schedule", NotificationManager.IMPORTANCE_DEFAULT),
            NotificationChannel(CHANNEL_FOCUS, "Focus", NotificationManager.IMPORTANCE_DEFAULT),
        )
        channels.forEach { mgr.createNotificationChannel(it) }
    }

    fun scheduleAll(plans: List<PlannedNotification>) {
        ensureChannels()
        // Cancel previously known keys by reusing stable ids when possible.
        plans.forEach { schedule(it) }
    }

    fun schedule(plan: PlannedNotification) {
        val alarm = context.getSystemService(AlarmManager::class.java) ?: return
        val intent = Intent(context, NotificationAlarmReceiver::class.java).apply {
            action = ACTION_FIRE
            putExtra(EXTRA_ID, plan.id)
            putExtra(EXTRA_TITLE, plan.title)
            putExtra(EXTRA_BODY, plan.body)
            putExtra(EXTRA_KIND, plan.kind.name)
        }
        val requestCode = plan.id.hashCode()
        val pending = PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val triggerAt = plan.fireAt.toEpochMilli().coerceAtLeast(System.currentTimeMillis())
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending)
            } else {
                alarm.set(AlarmManager.RTC_WAKEUP, triggerAt, pending)
            }
        }
        // Immediate fires (already due) post now.
        if (!plan.fireAt.isAfter(Instant.now().plusSeconds(2))) {
            postNow(plan)
        }
    }

    fun postNow(plan: PlannedNotification) {
        if (!canPost()) return
        val channel = when (plan.kind) {
            NotificationKind.MEDICATION_DUE -> CHANNEL_CARE
            NotificationKind.FOCUS_COMPLETE -> CHANNEL_FOCUS
            else -> CHANNEL_SCHEDULE
        }
        val open = PendingIntent.getActivity(
            context,
            plan.id.hashCode() xor 0x1111,
            Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notif = NotificationCompat.Builder(context, channel)
            .setSmallIcon(android.R.drawable.ic_menu_today)
            .setContentTitle(plan.title)
            .setContentText(plan.body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(plan.body))
            .setContentIntent(open)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()
        NotificationManagerCompat.from(context)
            .notify(plan.id.hashCode(), notif)
    }

    private fun canPost(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
    }

    companion object {
        const val ACTION_FIRE = "com.lookafter.app.NOTIFY_FIRE"
        const val EXTRA_ID = "id"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val EXTRA_KIND = "kind"
        const val CHANNEL_CARE = "lookafter_care"
        const val CHANNEL_SCHEDULE = "lookafter_schedule"
        const val CHANNEL_FOCUS = "lookafter_focus"
    }
}

class NotificationAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != LookAfterNotifier.ACTION_FIRE) return
        val plan = PlannedNotification(
            id = intent.getStringExtra(LookAfterNotifier.EXTRA_ID) ?: return,
            kind = runCatching {
                NotificationKind.valueOf(
                    intent.getStringExtra(LookAfterNotifier.EXTRA_KIND)
                        ?: NotificationKind.DAILY_BRIEFING.name,
                )
            }.getOrDefault(NotificationKind.DAILY_BRIEFING),
            title = intent.getStringExtra(LookAfterNotifier.EXTRA_TITLE) ?: "Look After",
            body = intent.getStringExtra(LookAfterNotifier.EXTRA_BODY) ?: "",
            fireAt = Instant.now(),
        )
        LookAfterNotifier(context.applicationContext).postNow(plan)
    }
}
