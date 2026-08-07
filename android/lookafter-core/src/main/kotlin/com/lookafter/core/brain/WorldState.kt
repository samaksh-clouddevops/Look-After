package com.lookafter.core.brain

import com.lookafter.core.health.HealthSummary
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.Medication
import com.lookafter.core.serialization.InstantSerializer
import java.time.Instant
import kotlinx.serialization.Serializable

/** Cognitive load band — mirrors iOS CognitiveLoadLevel. */
@Serializable
enum class CognitiveLoadLevel { LOW, MODERATE, HIGH, OVERLOADED }

/** Sleep quality band. */
@Serializable
enum class SleepQuality { UNKNOWN, POOR, FAIR, GOOD, EXCELLENT }

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
 * Pure data — UI and coach read this; never recompute ad-hoc in views.
 * Mirrors iOS ExecutiveBrain.WorldState (subset).
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
