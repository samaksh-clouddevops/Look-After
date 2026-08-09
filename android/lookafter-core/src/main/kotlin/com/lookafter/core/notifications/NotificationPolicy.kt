package com.lookafter.core.notifications

import com.lookafter.core.brain.MedicationWorldStatus
import com.lookafter.core.brain.WorldState
import com.lookafter.core.engine.LifeState
import com.lookafter.core.models.ConstraintType
import java.time.Duration
import java.time.Instant
import java.time.ZoneId

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
    val anchoredEnabled: Boolean = true,
    val briefingEnabled: Boolean = true,
    val focusCompleteEnabled: Boolean = true,
    val anchoredLeadMinutes: Int = 15,
    val quietHoursEnabled: Boolean = true,
    val quietHoursStartHour: Int = 22,
    val quietHoursEndHour: Int = 7,
    val suppressDuringFocus: Boolean = true,
)

/**
 * Pure notification planner — no Android NotificationManager.
 * Respects preference toggles + quiet hours. App layer schedules results.
 */
object NotificationPolicy {

    fun plan(
        life: LifeState,
        world: WorldState,
        now: Instant = Instant.now(),
        inFocusSession: Boolean = false,
        config: NotificationPolicyConfig = NotificationPolicyConfig(),
        zone: ZoneId = ZoneId.systemDefault(),
    ): List<PlannedNotification> {
        if (config.suppressDuringFocus && inFocusSession) return emptyList()

        val prefs = NotificationPreferences(
            medicationsEnabled = config.medicationsEnabled,
            anchoredEnabled = config.anchoredEnabled,
            briefingEnabled = config.briefingEnabled,
            focusCompleteEnabled = config.focusCompleteEnabled,
            anchoredLeadMinutes = config.anchoredLeadMinutes,
            quietHoursEnabled = config.quietHoursEnabled,
            quietHoursStartHour = config.quietHoursStartHour,
            quietHoursEndHour = config.quietHoursEndHour,
            suppressDuringFocus = config.suppressDuringFocus,
        )

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

        if (config.anchoredEnabled) {
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
        }

        if (config.briefingEnabled && world.openTaskCount >= 3 && world.completedTodayCount == 0) {
            out += PlannedNotification(
                id = "briefing-morning",
                kind = NotificationKind.DAILY_BRIEFING,
                title = "Your day is ready",
                body = "${world.openTaskCount} open · hero: check Briefing",
                fireAt = now,
            )
        }

        return out
            .filterNot { prefs.isInQuietHours(it.fireAt, zone) }
            .distinctBy { it.id }
    }
}
