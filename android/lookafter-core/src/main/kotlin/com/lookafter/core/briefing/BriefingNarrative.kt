package com.lookafter.core.briefing

import com.lookafter.core.brain.BrainTick
import com.lookafter.core.brain.ExecutiveBrainEngine
import com.lookafter.core.brain.MedicationWorldStatus
import com.lookafter.core.capacity.CapacityBand
import com.lookafter.core.capacity.ExecutiveCapacity
import com.lookafter.core.capacity.ExecutiveCapacityEngine
import com.lookafter.core.cycle.CycleSnapshot
import com.lookafter.core.engine.LifeState
import com.lookafter.core.health.HealthSummary
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.TaskStatus
import com.lookafter.core.today.TodayBoard
import java.time.LocalDate
import java.time.LocalTime
import kotlinx.serialization.Serializable

@Serializable
data class BriefingLine(
    val eyebrow: String,
    val body: String,
)

/**
 * Full morning briefing script derived from LifeState + health + capacity + brain.
 * Pure — Compose only renders.
 */
@Serializable
data class BriefingNarrative(
    val greeting: String = "Good day",
    val dayLabel: String = "",
    val orientation: String = "",
    val heroTitle: String = "Nothing queued",
    val heroReason: String = "Protect the quiet.",
    val heroTaskId: String? = null,
    val capacity: ExecutiveCapacity = ExecutiveCapacity.EMPTY,
    val careLine: String? = null,
    val calendarLine: String? = null,
    val cycleLine: String? = null,
    val boardLine: String = "",
    val guidance: List<BriefingLine> = emptyList(),
    val focusCtaLabel: String = "Begin focus",
    val showFocusCta: Boolean = false,
) {
    companion object {
        val EMPTY = BriefingNarrative()
    }
}

object BriefingNarrativeBuilder {

    fun build(
        state: LifeState,
        health: HealthSummary = HealthSummary.EMPTY,
        tick: BrainTick = ExecutiveBrainEngine.tick(state, health),
        capacity: ExecutiveCapacity = ExecutiveCapacityEngine.compute(state, health, tick.world),
        day: LocalDate = state.currentDay ?: LocalDate.now(),
        nowTime: LocalTime = LocalTime.now(),
        cycle: CycleSnapshot = CycleSnapshot(),
    ): BriefingNarrative {
        val dayTasks = TodayBoard.dayTasks(state, day)
        val open = dayTasks.count { it.status.isActive }
        val done = dayTasks.count { it.status == TaskStatus.COMPLETED }
        val anchored = dayTasks.count {
            it.status.isActive && it.constraintType == ConstraintType.ANCHORED
        }
        val greeting = greetingFor(nowTime)
        val orientation = buildOrientation(capacity, open, done, tick)
        val care = careLine(tick.world.medicationStatus, state)
        val calendar = calendarLine(tick)
        val cycleLine = cycleLine(cycle)
        val board = when {
            open == 0 && done == 0 -> "Board is empty — capture lightly or rest."
            open == 0 -> "All clear for the day view · $done done."
            else -> "$open open · $done done · $anchored anchored"
        }
        val guidance = buildGuidance(capacity, tick, care != null, cycle)

        return BriefingNarrative(
            greeting = greeting,
            dayLabel = day.toString(),
            orientation = orientation,
            heroTitle = tick.decision.heroTitle,
            heroReason = tick.decision.reason.ifBlank { capacity.band.coachingHint },
            heroTaskId = tick.decision.heroTaskId,
            capacity = capacity,
            careLine = care,
            calendarLine = calendar,
            cycleLine = cycleLine,
            boardLine = board,
            guidance = guidance,
            focusCtaLabel = if (tick.decision.heroTaskId != null) "Begin focus" else "Open Today",
            showFocusCta = tick.decision.heroTaskId != null || open > 0,
        )
    }

    private fun cycleLine(cycle: CycleSnapshot): String? {
        if (!cycle.trackingEnabled) return null
        val dayPart = cycle.dayInCycle?.let { " · day $it" }.orEmpty()
        return "Cycle: ${cycle.phaseLabel}$dayPart — ${cycle.coachingHint}"
    }

    private fun greetingFor(t: LocalTime): String = when (t.hour) {
        in 5..11 -> "Good morning"
        in 12..16 -> "Good afternoon"
        in 17..21 -> "Good evening"
        else -> "Still here"
    }

    private fun buildOrientation(
        capacity: ExecutiveCapacity,
        open: Int,
        done: Int,
        tick: BrainTick,
    ): String {
        val energyPct = (capacity.energyScore * 100).toInt()
        val base = "Energy ~$energyPct% · ${capacity.band.label.lowercase()} · " +
            "favor ~${capacity.recommendedFocusMinutes}m deep work"
        return when {
            capacity.isOverCommitted ->
                "$base. Board is heavy — strip noise before adding more."
            capacity.band == CapacityBand.RECOVERY ->
                "$base. Keep blocks short; care first."
            open == 0 && done > 0 ->
                "$base. Momentum is available if you want a light capture."
            tick.world.healthReadiness < 0.4 ->
                "$base. Readiness is low — protect recovery."
            else -> base
        }
    }

    private fun careLine(status: MedicationWorldStatus, state: LifeState): String? = when (status) {
        is MedicationWorldStatus.DueNow ->
            "Care: take ${status.names.joinToString()} before the next block."
        is MedicationWorldStatus.MissedToday ->
            "Care: still open — ${status.names.joinToString()}. Reset gently."
        is MedicationWorldStatus.Upcoming ->
            "Care: upcoming ${status.names.joinToString()}."
        MedicationWorldStatus.AllTakenToday ->
            if (state.medications.isNotEmpty()) "Care: meds marked taken. Nice." else null
        else -> if (state.medications.isEmpty()) null else null
    }

    private fun calendarLine(tick: BrainTick): String? {
        val title = tick.world.nextEventTitle ?: return null
        val mins = tick.world.minutesUntilNextEvent
        return if (mins != null) {
            "Calendar: $title in ${mins}m"
        } else {
            "Calendar: next — $title"
        }
    }

    private fun buildGuidance(
        capacity: ExecutiveCapacity,
        tick: BrainTick,
        hasCare: Boolean,
        cycle: CycleSnapshot = CycleSnapshot(),
    ): List<BriefingLine> {
        val lines = mutableListOf<BriefingLine>()
        lines += BriefingLine("Capacity", capacity.band.coachingHint)
        if (cycle.trackingEnabled && cycle.phase != com.lookafter.core.cycle.CyclePhase.UNKNOWN) {
            lines += BriefingLine("Cycle", cycle.coachingHint)
        }
        if (hasCare) {
            lines += BriefingLine("Sequence", "Care → hero → optional fluid.")
        } else {
            lines += BriefingLine("Sequence", "Hero first. Fluid waits.")
        }
        if (capacity.isOverCommitted) {
            lines += BriefingLine("Board", "Park fluid. Leave anchored. One intentional block.")
        } else if (tick.world.openTaskCount <= 1) {
            lines += BriefingLine("Board", "Keep it sparse — quiet is a feature.")
        } else {
            lines += BriefingLine(
                "Board",
                "Aim for ≤${capacity.recommendedOpenTasks} open active items.",
            )
        }
        capacity.reasons.take(2).forEach {
            lines += BriefingLine("Signal", it)
        }
        return lines.take(6)
    }
}
