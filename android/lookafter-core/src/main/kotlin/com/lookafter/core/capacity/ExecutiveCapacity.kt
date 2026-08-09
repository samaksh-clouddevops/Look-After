package com.lookafter.core.capacity

import com.lookafter.core.brain.CognitiveLoadLevel
import com.lookafter.core.brain.WorldState
import com.lookafter.core.engine.LifeState
import com.lookafter.core.health.HealthSummary
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.TaskStatus
import com.lookafter.core.today.TodayBoard
import java.time.LocalDate
import kotlinx.serialization.Serializable

/** Energy / capacity band for the operational day. */
@Serializable
enum class CapacityBand {
    RECOVERY,
    PROTECTIVE,
    STEADY,
    HIGH,
    ;

    val label: String
        get() = when (this) {
            RECOVERY -> "Recovery"
            PROTECTIVE -> "Protective"
            STEADY -> "Steady"
            HIGH -> "High"
        }

    val coachingHint: String
        get() = when (this) {
            RECOVERY -> "Short blocks only. Prefer rest and due care."
            PROTECTIVE -> "One hero. Guard buffers; skip optional load."
            STEADY -> "Normal cadence — keep the board narrow."
            HIGH -> "You can push, but still finish what you start."
        }
}

/**
 * Pure executive capacity model — energy budget for the day.
 * Consumed by Briefing, Brain, and planning (never recompute ad-hoc in UI).
 */
@Serializable
data class ExecutiveCapacity(
    val band: CapacityBand = CapacityBand.STEADY,
    /** 0..1 composite energy score. */
    val energyScore: Double = 0.55,
    /** Suggested max deep-work minutes for remaining day. */
    val recommendedFocusMinutes: Int = 90,
    /** Suggested max concurrent open active tasks. */
    val recommendedOpenTasks: Int = 5,
    val plannedOpenMinutes: Int = 0,
    val isOverCommitted: Boolean = false,
    val reasons: List<String> = emptyList(),
    val headline: String = "Steady capacity",
) {
    companion object {
        val EMPTY = ExecutiveCapacity()
    }
}

object ExecutiveCapacityEngine {

    fun compute(
        state: LifeState,
        health: HealthSummary = HealthSummary.EMPTY,
        world: WorldState = WorldState.EMPTY,
        day: LocalDate = state.currentDay ?: LocalDate.now(),
    ): ExecutiveCapacity {
        val dayTasks = TodayBoard.dayTasks(state, day)
        val open = dayTasks.filter { it.status.isActive }
        val openMinutes = open.sumOf { it.durationMinutes.coerceAtLeast(0) }
        val anchored = open.count { it.constraintType == ConstraintType.ANCHORED }

        val readiness = health.readinessScore
            ?: world.healthReadiness.takeIf { world != WorldState.EMPTY }
            ?: 0.55
        val sleepH = health.sleepHours ?: world.sleepHoursLastNight
        val load = world.cognitiveLoad

        var energy = readiness.coerceIn(0.0, 1.0)
        val reasons = mutableListOf<String>()

        when {
            sleepH == null -> Unit
            sleepH < 5.5 -> {
                energy -= 0.18
                reasons += "Short sleep (${"%.1f".format(sleepH)}h)"
            }
            sleepH < 6.5 -> {
                energy -= 0.08
                reasons += "Modest sleep"
            }
            sleepH >= 7.5 -> {
                energy += 0.06
                reasons += "Solid sleep"
            }
        }

        when (load) {
            CognitiveLoadLevel.OVERLOADED -> {
                energy -= 0.2
                reasons += "Cognitive load overloaded"
            }
            CognitiveLoadLevel.HIGH -> {
                energy -= 0.1
                reasons += "High cognitive load"
            }
            CognitiveLoadLevel.LOW -> energy += 0.05
            CognitiveLoadLevel.MODERATE -> Unit
        }

        if (world.consecutiveHighLoadDays >= 2) {
            energy -= 0.08
            reasons += "${world.consecutiveHighLoadDays} high-load days"
        }
        if (anchored >= 4 || world.isMeetingHeavyDay) {
            energy -= 0.1
            reasons += "Meeting-heavy shape"
        }
        when (val med = world.medicationStatus) {
            is com.lookafter.core.brain.MedicationWorldStatus.DueNow -> {
                energy -= 0.05
                reasons += "Meds due: ${med.names.joinToString()}"
            }
            is com.lookafter.core.brain.MedicationWorldStatus.MissedToday -> {
                energy -= 0.08
                reasons += "Missed meds"
            }
            else -> Unit
        }

        energy = energy.coerceIn(0.05, 0.98)
        val band = bandFor(energy, openMinutes)
        val focusMins = when (band) {
            CapacityBand.RECOVERY -> 35
            CapacityBand.PROTECTIVE -> 60
            CapacityBand.STEADY -> 110
            CapacityBand.HIGH -> 160
        }
        val openCap = when (band) {
            CapacityBand.RECOVERY -> 3
            CapacityBand.PROTECTIVE -> 4
            CapacityBand.STEADY -> 6
            CapacityBand.HIGH -> 8
        }
        val over = openMinutes > focusMins * 2 || open.size > openCap + 2
        if (over) reasons += "Board exceeds capacity envelope"

        return ExecutiveCapacity(
            band = band,
            energyScore = energy,
            recommendedFocusMinutes = focusMins,
            recommendedOpenTasks = openCap,
            plannedOpenMinutes = openMinutes,
            isOverCommitted = over,
            reasons = reasons.distinct().take(5),
            headline = when {
                over -> "Over committed · ${band.label.lowercase()} energy"
                else -> "${band.label} capacity"
            },
        )
    }

    private fun bandFor(energy: Double, openMinutes: Int): CapacityBand = when {
        energy < 0.35 || openMinutes >= 7 * 60 -> CapacityBand.RECOVERY
        energy < 0.5 -> CapacityBand.PROTECTIVE
        energy < 0.72 -> CapacityBand.STEADY
        else -> CapacityBand.HIGH
    }
}
