package com.lookafter.core.cycle

import com.lookafter.core.serialization.LocalDateSerializer
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import java.util.UUID
import kotlinx.serialization.Serializable

@Serializable
enum class CyclePhase {
    MENSTRUAL,
    FOLLICULAR,
    OVULATORY,
    LUTEAL,
    UNKNOWN,
    ;

    val label: String
        get() = when (this) {
            MENSTRUAL -> "Menstrual"
            FOLLICULAR -> "Follicular"
            OVULATORY -> "Ovulatory"
            LUTEAL -> "Luteal"
            UNKNOWN -> "Unknown"
        }

    /** Short privacy-minded coaching tip. */
    val coachingHint: String
        get() = when (this) {
            MENSTRUAL -> "Energy may dip — shorten blocks and protect rest."
            FOLLICULAR -> "Rising energy — good window for new work."
            OVULATORY -> "Peak social/verbal energy — favor collaboration."
            LUTEAL -> "Protect buffers; prefer finish work over new load."
            UNKNOWN -> "Log a period start when you want phase-aware capacity."
        }
}

@Serializable
data class CycleLogEntry(
    val id: String = UUID.randomUUID().toString(),
    @Serializable(with = LocalDateSerializer::class)
    val date: LocalDate,
    /** Free-text symptom / note (local-only). */
    val note: String = "",
    val energy: Int? = null, // 1–5 optional
    val isPeriodDay: Boolean = false,
)

@Serializable
data class CycleSettings(
    val trackingEnabled: Boolean = false,
    val averageCycleLengthDays: Int = 28,
    val averagePeriodLengthDays: Int = 5,
    @Serializable(with = LocalDateSerializer::class)
    val lastPeriodStart: LocalDate? = null,
)

@Serializable
data class CycleSnapshot(
    val phase: CyclePhase = CyclePhase.UNKNOWN,
    val dayInCycle: Int? = null,
    val trackingEnabled: Boolean = false,
    val capacityModifier: Double = 0.0,
    val phaseLabel: String = CyclePhase.UNKNOWN.label,
    val coachingHint: String = CyclePhase.UNKNOWN.coachingHint,
)

@Serializable
data class CycleState(
    val settings: CycleSettings = CycleSettings(),
    val logs: List<CycleLogEntry> = emptyList(),
) {
    companion object {
        val EMPTY = CycleState()
    }
}

sealed class CycleIntent {
    data class SetTrackingEnabled(val enabled: Boolean) : CycleIntent()
    data class SetLastPeriodStart(val day: LocalDate?) : CycleIntent()
    data class SetCycleLength(val days: Int) : CycleIntent()
    data class SetPeriodLength(val days: Int) : CycleIntent()
    data class AddLog(val entry: CycleLogEntry) : CycleIntent()
    data class DeleteLog(val id: String) : CycleIntent()
    data class ReplaceState(val state: CycleState) : CycleIntent()
}

/**
 * Pure cycle phase + capacity modifier (Phase E2).
 * Privacy-first: all local; modifier only applied when tracking is enabled.
 */
object CycleEngine {

    fun reduce(current: CycleState, intent: CycleIntent): CycleState = when (intent) {
        is CycleIntent.SetTrackingEnabled -> current.copy(
            settings = current.settings.copy(trackingEnabled = intent.enabled),
        )
        is CycleIntent.SetLastPeriodStart -> current.copy(
            settings = current.settings.copy(lastPeriodStart = intent.day),
        )
        is CycleIntent.SetCycleLength -> current.copy(
            settings = current.settings.copy(
                averageCycleLengthDays = intent.days.coerceIn(21, 40),
            ),
        )
        is CycleIntent.SetPeriodLength -> current.copy(
            settings = current.settings.copy(
                averagePeriodLengthDays = intent.days.coerceIn(2, 10),
            ),
        )
        is CycleIntent.AddLog -> current.copy(
            logs = (listOf(intent.entry) + current.logs)
                .sortedByDescending { it.date }
                .take(120),
        )
        is CycleIntent.DeleteLog -> current.copy(
            logs = current.logs.filterNot { it.id == intent.id },
        )
        is CycleIntent.ReplaceState -> intent.state
    }

    fun snapshot(
        state: CycleState,
        today: LocalDate = LocalDate.now(),
    ): CycleSnapshot {
        if (!state.settings.trackingEnabled) {
            return CycleSnapshot(trackingEnabled = false)
        }
        val start = state.settings.lastPeriodStart
            ?: state.logs.filter { it.isPeriodDay }.maxByOrNull { it.date }?.date
            ?: return CycleSnapshot(
                trackingEnabled = true,
                coachingHint = "Add a period start date to unlock phases.",
            )
        val cycleLen = state.settings.averageCycleLengthDays.coerceIn(21, 40)
        val periodLen = state.settings.averagePeriodLengthDays.coerceIn(2, 10)
        val dayIndex = ChronoUnit.DAYS.between(start, today).toInt()
        if (dayIndex < 0) {
            return CycleSnapshot(trackingEnabled = true, phase = CyclePhase.UNKNOWN)
        }
        val dayInCycle = (dayIndex % cycleLen) + 1
        val phase = phaseForDay(dayInCycle, periodLen, cycleLen)
        val modifier = capacityModifier(phase)
        return CycleSnapshot(
            phase = phase,
            dayInCycle = dayInCycle,
            trackingEnabled = true,
            capacityModifier = modifier,
            phaseLabel = phase.label,
            coachingHint = phase.coachingHint,
        )
    }

    /**
     * Energy adjustment in [-0.12, +0.08] applied inside ExecutiveCapacity.
     * Matches iOS directionality (luteal/menstrual lower, follicular/ovulatory higher).
     */
    fun capacityModifier(phase: CyclePhase): Double = when (phase) {
        CyclePhase.MENSTRUAL -> -0.10
        CyclePhase.FOLLICULAR -> 0.05
        CyclePhase.OVULATORY -> 0.08
        CyclePhase.LUTEAL -> -0.07
        CyclePhase.UNKNOWN -> 0.0
    }

    private fun phaseForDay(dayInCycle: Int, periodLen: Int, cycleLen: Int): CyclePhase {
        val d = dayInCycle.coerceIn(1, cycleLen)
        val menstrualEnd = periodLen
        val ovulatoryStart = (cycleLen / 2 - 1).coerceAtLeast(menstrualEnd + 2)
        val ovulatoryEnd = (cycleLen / 2 + 1).coerceAtMost(cycleLen - 4)
        return when {
            d <= menstrualEnd -> CyclePhase.MENSTRUAL
            d < ovulatoryStart -> CyclePhase.FOLLICULAR
            d <= ovulatoryEnd -> CyclePhase.OVULATORY
            else -> CyclePhase.LUTEAL
        }
    }
}
