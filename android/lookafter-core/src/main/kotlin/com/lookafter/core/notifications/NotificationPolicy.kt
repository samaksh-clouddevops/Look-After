package com.lookafter.core.notifications

import com.lookafter.core.brain.MedicationWorldStatus
import com.lookafter.core.brain.WorldState
import com.lookafter.core.engine.LifeState
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.TaskStatus
import java.time.Duration
import java.time.Instant

enum class NotificationKind { MEDICATION_DUE, ANCHORED_SOON, DAILY_BRIEFING, FOCUS_COMPLETE }

data class PlannedNotification(
    val id: String,
    val kind: NotificationKind,
    val title: String,
    val body: String,
    val fireAt: Instant,
)

data class NotificationPolicyConfig(
    val medicationsEnabled: Boolean = true,
    val anchoredLeadMinutes: Int = 15,
    val quietHoursStart: Int = 22, // 22:00 local hours as wall int — pure policy uses Instant windows
    val quietHoursEnd: Int = 7,
    val suppressDuringFocus: Boolean = true,
)

/**
 * Pure notification planner — no Android NotificationManager.
 * App layer schedules the returned [PlannedNotification]s.
 */
object NotificationPolicy {

    fun plan(
        life: LifeState,
        world: WorldState,
        now: Instant = Instant.now(),
        inFocusSession: Boolean = false,
        config: NotificationPolicyConfig = NotificationPolicyConfig(),
    ): List<PlannedNotification> {
        if (config.suppressDuringFocus && inFocusSession) return emptyList()

        val out = mutableListOf<PlannedNotification>()

        if (config.medicationsEnabled) {
            when (val med = world.medicationStatus) {
                is MedicationWorldStatus.DueNow -> {
                    out += PlannedNotification(
                        id = "med-due",
                        kind = NotificationKind.MEDICATION_DUE,
                        title = "Medication due",
                        body = med.names.joinToString(),
                        fireAt = now,
                    )
                }
                else -> Unit
            }
        }

        life.activeTasks
            .filter { it.status.isActive && it.constraintType == ConstraintType.ANCHORED }
            .forEach { task ->
                val start = task.scheduledStart ?: return@forEach
                val lead = start.minus(Duration.ofMinutes(config.anchoredLeadMinutes.toLong()))
                if (!lead.isBefore(now) && Duration.between(now, lead).toMinutes() <= 24 * 60) {
                    out += PlannedNotification(
                        id = "anchored-${task.id}",
                        kind = NotificationKind.ANCHORED_SOON,
                        title = "Upcoming: ${task.title}",
                        body = "Starts in ${config.anchoredLeadMinutes} minutes",
                        fireAt = lead,
                    )
                }
            }

        // Soft morning briefing nudge once after 07:30 if many open tasks.
        if (world.openTaskCount >= 3 && world.completedTodayCount == 0) {
            out += PlannedNotification(
                id = "briefing-morning",
                kind = NotificationKind.DAILY_BRIEFING,
                title = "Your day is ready",
                body = "${world.openTaskCount} open · hero: check Briefing",
                fireAt = now,
            )
        }

        return out.distinctBy { it.id }
    }
}
