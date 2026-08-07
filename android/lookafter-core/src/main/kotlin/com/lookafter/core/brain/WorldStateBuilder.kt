package com.lookafter.core.brain

import com.lookafter.core.engine.LifeState
import com.lookafter.core.health.HealthSummary
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.Medication
import com.lookafter.core.models.TaskStatus
import java.time.Duration
import java.time.Instant
import java.time.ZoneId

/**
 * Pure WorldState projection from [LifeState] + [HealthSummary] + optional calendar.
 * Mirrors iOS WorldStateBuilder (deterministic subset).
 */
object WorldStateBuilder {

    data class CalendarEvent(
        val title: String,
        val start: Instant,
        val end: Instant? = null,
    )

    data class Input(
        val life: LifeState,
        val health: HealthSummary = HealthSummary.EMPTY,
        val now: Instant = Instant.now(),
        val zone: ZoneId = ZoneId.systemDefault(),
        val calendarEvents: List<CalendarEvent> = emptyList(),
        val unpurchasedShoppingCount: Int = 0,
        val unpaidBillsCount: Int = 0,
        val isInFlowSession: Boolean = false,
    )

    fun build(input: Input): WorldState {
        val hero = HeroTaskRanker.select(input.life, input.now)
        val open = input.life.activeTasks.filter { it.status.isActive }
        val done = input.life.activeTasks.count { it.status == TaskStatus.COMPLETED }
        val nextCal = input.calendarEvents
            .filter { it.start.isAfter(input.now) }
            .minByOrNull { it.start }
        val minutesUntil = nextCal?.let {
            Duration.between(input.now, it.start).toMinutes().toInt().coerceAtLeast(0)
        }
        val meetingCount = input.calendarEvents.count {
            Duration.between(input.now.minus(Duration.ofHours(12)), it.start).toHours() in 0..16
        }
        val sleepH = input.health.sleepHours
        val readiness = input.health.readinessScore ?: 0.5
        val energy = readiness.coerceIn(0.0, 1.0)
        val load = cognitiveLoad(open.size, meetingCount, readiness)
        val available = availableMinutes(open, nextCal, input.now)

        return WorldState(
            generatedAt = input.now,
            currentEnergy = energy,
            cognitiveLoad = load,
            sleepHoursLastNight = sleepH,
            sleepQuality = sleepQuality(sleepH, input.health.sleepQualityScore),
            healthReadiness = readiness,
            availableMinutes = available,
            minutesUntilNextEvent = minutesUntil,
            nextEventTitle = nextCal?.title,
            isMeetingHeavyDay = meetingCount >= 4,
            consecutiveHighLoadDays = input.life.consecutiveHighLoadDays,
            heroTaskId = hero.task?.id,
            heroReason = hero.reason,
            topTaskIds = open.sortedBy { it.scheduledStart ?: Instant.MAX }.take(5).map { it.id },
            medicationStatus = medicationStatus(input.life.medications, input.now, input.zone),
            unpurchasedShoppingCount = input.unpurchasedShoppingCount,
            unpaidBillsCount = input.unpaidBillsCount,
            isInFlowSession = input.isInFlowSession ||
                open.any { it.status == TaskStatus.IN_PROGRESS },
            openTaskCount = open.size,
            completedTodayCount = done,
        )
    }

    private fun cognitiveLoad(open: Int, meetings: Int, readiness: Double): CognitiveLoadLevel {
        val pressure = open + meetings * 2 - (if (readiness >= 0.7) 1 else 0)
        return when {
            pressure >= 12 -> CognitiveLoadLevel.OVERLOADED
            pressure >= 8 -> CognitiveLoadLevel.HIGH
            pressure >= 4 -> CognitiveLoadLevel.MODERATE
            else -> CognitiveLoadLevel.LOW
        }
    }

    private fun sleepQuality(hours: Double?, score: Double?): SleepQuality {
        val h = hours ?: return SleepQuality.UNKNOWN
        val s = score ?: (h / 8.0).coerceIn(0.0, 1.0)
        return when {
            s >= 0.85 || h >= 7.5 -> SleepQuality.EXCELLENT
            s >= 0.7 || h >= 6.5 -> SleepQuality.GOOD
            s >= 0.5 || h >= 5.5 -> SleepQuality.FAIR
            else -> SleepQuality.POOR
        }
    }

    private fun availableMinutes(
        open: List<com.lookafter.core.models.LifeTask>,
        next: CalendarEvent?,
        now: Instant,
    ): Int {
        val untilMeeting = next?.let {
            Duration.between(now, it.start).toMinutes().toInt().coerceAtLeast(0)
        } ?: 8 * 60
        val remainingWork = open.sumOf { it.durationMinutes }
        return minOf(untilMeeting, remainingWork.coerceAtLeast(0), 8 * 60)
    }

    private fun medicationStatus(
        meds: List<Medication>,
        now: Instant,
        zone: ZoneId,
    ): MedicationWorldStatus {
        if (meds.isEmpty()) return MedicationWorldStatus.NoneConfigured
        val local = now.atZone(zone).toLocalTime()
        val untaken = meds.filter { !it.isTaken }
        if (untaken.isEmpty()) return MedicationWorldStatus.AllTakenToday
        // Due = scheduled at or before now (same calendar day).
        val due = untaken.filter { !it.scheduledTime.isAfter(local) }
        if (due.isNotEmpty()) return MedicationWorldStatus.DueNow(due.map { it.name })
        val upcoming = untaken.filter { it.scheduledTime.isAfter(local) }.take(3)
        if (upcoming.isNotEmpty()) return MedicationWorldStatus.Upcoming(upcoming.map { it.name })
        return MedicationWorldStatus.MissedToday(untaken.map { it.name })
    }
}
