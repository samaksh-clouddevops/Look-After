package com.lookafter.core.brain

import com.lookafter.core.capacity.ExecutiveCapacityEngine
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
 * Phase B2: calendar density, capacity snapshot, med risk, board pressure.
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
        val windowStart = input.now.minus(Duration.ofHours(4))
        val windowEnd = input.now.plus(Duration.ofHours(14))
        val dayEvents = input.calendarEvents.filter {
            !it.start.isBefore(windowStart) && it.start.isBefore(windowEnd)
        }
        val meetingCount = dayEvents.size
        val density = calendarDensity(meetingCount)
        val sleepH = input.health.sleepHours
        val readiness = input.health.readinessScore ?: 0.5
        val energy = readiness.coerceIn(0.0, 1.0)
        val load = cognitiveLoad(open.size, meetingCount, readiness)
        val available = availableMinutes(open, nextCal, input.now)
        val medStatus = medicationStatus(input.life.medications, input.now, input.zone)
        val medRisk = medicationRisk(medStatus)
        val plannedMinutes = open.sumOf { it.durationMinutes.coerceAtLeast(0) }
        val pressure = openTaskPressure(open.size, plannedMinutes)
        val anchored = open.count { it.constraintType == ConstraintType.ANCHORED }
        val flexible = open.count { it.constraintType == ConstraintType.FLEXIBLE }
        val fluid = open.count { it.constraintType == ConstraintType.FLUID }

        val preliminary = WorldState(
            generatedAt = input.now,
            currentEnergy = energy,
            cognitiveLoad = load,
            sleepHoursLastNight = sleepH,
            sleepQuality = sleepQuality(sleepH, input.health.sleepQualityScore),
            healthReadiness = readiness,
            availableMinutes = available,
            minutesUntilNextEvent = minutesUntil,
            nextEventTitle = nextCal?.title,
            isMeetingHeavyDay = density == CalendarDensity.PACKED || density == CalendarDensity.BUSY,
            calendarEventCount = meetingCount,
            calendarDensity = density,
            anchoredOpenCount = anchored,
            flexibleOpenCount = flexible,
            fluidOpenCount = fluid,
            openTaskPressure = pressure,
            medicationRisk = medRisk,
            consecutiveHighLoadDays = input.life.consecutiveHighLoadDays,
            heroTaskId = hero.task?.id,
            heroReason = hero.reason,
            topTaskIds = open.sortedBy { it.scheduledStart ?: Instant.MAX }.take(5).map { it.id },
            medicationStatus = medStatus,
            unpurchasedShoppingCount = input.unpurchasedShoppingCount,
            unpaidBillsCount = input.unpaidBillsCount,
            isInFlowSession = input.isInFlowSession ||
                open.any { it.status == TaskStatus.IN_PROGRESS },
            openTaskCount = open.size,
            completedTodayCount = done,
            plannedOpenMinutes = plannedMinutes,
        )
        val capacity = ExecutiveCapacityEngine.compute(input.life, input.health, preliminary)
        return preliminary.copy(
            capacityBand = capacity.band,
            capacityEnergyScore = capacity.energyScore,
            recommendedFocusMinutes = capacity.recommendedFocusMinutes,
            isOverCommitted = capacity.isOverCommitted,
            currentEnergy = capacity.energyScore,
        )
    }

    private fun calendarDensity(meetingCount: Int): CalendarDensity = when {
        meetingCount <= 0 -> CalendarDensity.CLEAR
        meetingCount <= 2 -> CalendarDensity.LIGHT
        meetingCount <= 4 -> CalendarDensity.BUSY
        else -> CalendarDensity.PACKED
    }

    private fun openTaskPressure(open: Int, plannedMinutes: Int): Double {
        val countPart = (open / 10.0).coerceIn(0.0, 1.0)
        val minutePart = (plannedMinutes / (8.0 * 60.0)).coerceIn(0.0, 1.0)
        return (countPart * 0.55 + minutePart * 0.45).coerceIn(0.0, 1.0)
    }

    private fun medicationRisk(status: MedicationWorldStatus): MedicationRisk = when (status) {
        is MedicationWorldStatus.DueNow -> MedicationRisk.DUE
        is MedicationWorldStatus.MissedToday -> MedicationRisk.MISSED
        is MedicationWorldStatus.Upcoming -> MedicationRisk.UPCOMING
        else -> MedicationRisk.NONE
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
        val due = untaken.filter { !it.scheduledTime.isAfter(local) }
        if (due.isNotEmpty()) return MedicationWorldStatus.DueNow(due.map { it.name })
        val upcoming = untaken.filter { it.scheduledTime.isAfter(local) }.take(3)
        if (upcoming.isNotEmpty()) return MedicationWorldStatus.Upcoming(upcoming.map { it.name })
        return MedicationWorldStatus.MissedToday(untaken.map { it.name })
    }
}
