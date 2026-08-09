package com.lookafter.core.brain

import com.lookafter.core.capacity.CapacityBand
import com.lookafter.core.models.LifeTask
import com.lookafter.core.serialization.InstantSerializer
import java.time.Instant
import kotlinx.serialization.Serializable

/** Cognitive load band — mirrors iOS CognitiveLoadLevel. */
@Serializable
enum class CognitiveLoadLevel { LOW, MODERATE, HIGH, OVERLOADED }

/** Sleep quality band. */
@Serializable
enum class SleepQuality { UNKNOWN, POOR, FAIR, GOOD, EXCELLENT }

/** Medication adherence risk for briefing/planning. */
@Serializable
enum class MedicationRisk {
    NONE,
    UPCOMING,
    DUE,
    MISSED,
    ;

    val label: String
        get() = when (this) {
            NONE -> "clear"
            UPCOMING -> "upcoming"
            DUE -> "due"
            MISSED -> "missed"
        }
}

/** Calendar pressure band for the operational day. */
@Serializable
enum class CalendarDensity {
    CLEAR,
    LIGHT,
    BUSY,
    PACKED,
    ;

    val label: String
        get() = name.lowercase()
}

/** Medication world status derived from configured inventory. */
@Serializable
sealed class MedicationWorldStatus {
    @Serializable data object Unknown : MedicationWorldStatus()
    @Serializable data object NoneConfigured : MedicationWorldStatus()
    @Serializable data object AllTakenToday : MedicationWorldStatus()
    @Serializable data class DueNow(val names: List<String>) : MedicationWorldStatus()
    @Serializable data class Upcoming(val names: List<String>) : MedicationWorldStatus()
    @Serializable data class MissedToday(val names: List<String>) : MedicationWorldStatus()
}

/**
 * Continuously-updated model of the user's operational day.
 * Pure data — UI, coach, and planners read this; never recompute ad-hoc in views.
 * Expanded toward iOS ExecutiveBrain.WorldState parity (Phase B2).
 */
@Serializable
data class WorldState(
    @Serializable(with = InstantSerializer::class)
    val generatedAt: Instant = Instant.EPOCH,
    val currentEnergy: Double = 0.5,
    val cognitiveLoad: CognitiveLoadLevel = CognitiveLoadLevel.MODERATE,
    val sleepHoursLastNight: Double? = null,
    val sleepQuality: SleepQuality = SleepQuality.UNKNOWN,
    val healthReadiness: Double = 0.5,
    val availableMinutes: Int = 0,
    val minutesUntilNextEvent: Int? = null,
    val nextEventTitle: String? = null,
    val isMeetingHeavyDay: Boolean = false,
    /** Distinct calendar events in the operational window. */
    val calendarEventCount: Int = 0,
    val calendarDensity: CalendarDensity = CalendarDensity.CLEAR,
    val anchoredOpenCount: Int = 0,
    val fluidOpenCount: Int = 0,
    val flexibleOpenCount: Int = 0,
    /** 0..1 board pressure from open count + minutes. */
    val openTaskPressure: Double = 0.0,
    val capacityBand: CapacityBand = CapacityBand.STEADY,
    val capacityEnergyScore: Double = 0.55,
    val recommendedFocusMinutes: Int = 90,
    val isOverCommitted: Boolean = false,
    val medicationRisk: MedicationRisk = MedicationRisk.NONE,
    val consecutiveHighLoadDays: Int = 0,
    val heroTaskId: String? = null,
    val heroReason: String = "",
    val topTaskIds: List<String> = emptyList(),
    val medicationStatus: MedicationWorldStatus = MedicationWorldStatus.Unknown,
    val unpurchasedShoppingCount: Int = 0,
    val unpaidBillsCount: Int = 0,
    val isInFlowSession: Boolean = false,
    val openTaskCount: Int = 0,
    val completedTodayCount: Int = 0,
    val plannedOpenMinutes: Int = 0,
) {
    companion object {
        val EMPTY = WorldState()
    }
}

/** Decision the offline Executive Brain emits for the hero surface. */
@Serializable
data class BrainDecision(
    val heroTaskId: String? = null,
    val heroTitle: String = "Nothing queued",
    val reason: String = "Protect the quiet.",
    val actionLabel: String = "Open Today",
    val confidence: Double = 0.5,
    val coachLine: String = "",
)

/** Full brain tick result for UI binding. */
@Serializable
data class BrainTick(
    val world: WorldState = WorldState.EMPTY,
    val decision: BrainDecision = BrainDecision(),
    val topTasks: List<LifeTask> = emptyList(),
)
