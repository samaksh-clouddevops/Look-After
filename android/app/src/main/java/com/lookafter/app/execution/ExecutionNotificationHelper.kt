package com.lookafter.app.execution

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.lookafter.app.MainActivity
import com.lookafter.app.R
import com.lookafter.core.models.ExecutionBlockSnapshot
import com.lookafter.core.models.ExecutionSurfaceMode
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Builds the ongoing lock-screen / drawer notification for the active focus block.
 * Low-importance channel so updates stay silent.
 */
class ExecutionNotificationHelper(private val context: Context) {

    private val manager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val existing = manager.getNotificationChannel(CHANNEL_ID)
        if (existing != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Active focus block on the lock screen"
            setShowBadge(false)
            enableVibration(false)
            setSound(null, null)
        }
        manager.createNotificationChannel(channel)
    }

    fun notify(snapshot: ExecutionBlockSnapshot) {
        manager.notify(NOTIFICATION_ID, build(snapshot))
    }

    /** Short-lived bootstrap notification to satisfy FGS start window. */
    fun buildBootstrap(): Notification {
        ensureChannel()
        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_recent_history)
            .setContentTitle(context.getString(R.string.app_name))
            .setContentText("Scanning for focus block…")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    fun build(snapshot: ExecutionBlockSnapshot): Notification {
        ensureChannel()
        val openApp = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val endLabel = formatEnd(snapshot)
        val badge = when (snapshot.surfaceMode) {
            ExecutionSurfaceMode.ANCHORED -> "Anchored Window"
            ExecutionSurfaceMode.FLEXIBLE -> "Flexible Block"
            else -> snapshot.constraintLabel
        }
        val text = buildString {
            append(badge)
            append(" · ends ")
            append(endLabel)
            if (snapshot.nextUpSummary.isNotBlank()) {
                append(" · ")
                append(snapshot.nextUpSummary)
            }
        }

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_recent_history)
            .setContentTitle(snapshot.taskTitle.ifBlank { context.getString(R.string.app_name) })
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setContentIntent(openApp)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setShowWhen(true)

        // Live countdown to window end.
        val endMillis = snapshot.windowEnd.toEpochMilli()
        if (endMillis > System.currentTimeMillis()) {
            builder
                .setUsesChronometer(true)
                .setChronometerCountDown(true)
                .setWhen(endMillis)
        } else {
            builder.setUsesChronometer(false)
        }

        val progress = (snapshot.progressFraction * 100).toInt().coerceIn(0, 100)
        builder.setProgress(100, progress, false)

        return builder.build()
    }

    private fun formatEnd(snapshot: ExecutionBlockSnapshot): String {
        val zone = ZoneId.systemDefault()
        val formatter = DateTimeFormatter.ofPattern("h:mm a", Locale.getDefault())
        return snapshot.windowEnd.atZone(zone).format(formatter)
    }

    companion object {
        const val CHANNEL_ID = "lookafter_execution"
        const val CHANNEL_NAME = "Focus Execution"
        const val NOTIFICATION_ID = 7101
    }
}
