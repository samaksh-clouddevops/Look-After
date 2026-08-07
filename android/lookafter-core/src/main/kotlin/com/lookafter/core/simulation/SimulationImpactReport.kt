package com.lookafter.core.simulation

import com.lookafter.core.engine.LifeState
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.TaskStatus

/**
 * Diff of a what-if cascade against the live baseline.
 * Positive deltas mean the hypothetical schedule made things worse/heavier.
 */
data class SimulationImpactReport(
    val parkedTaskDelta: Int = 0,
    val sabotageAuctionsTriggered: Int = 0,
    val supersededTasksDelta: Int = 0,
    val expiredTasksDelta: Int = 0,
    val highLoadStreakDelta: Int = 0,
    val activeTaskDelta: Int = 0,
    val shiftedLaterCount: Int = 0,
) {
    val hasDisruption: Boolean
        get() = parkedTaskDelta > 0 ||
            supersededTasksDelta > 0 ||
            expiredTasksDelta > 0 ||
            sabotageAuctionsTriggered > 0

    val summaryLine: String
        get() = buildList {
            if (parkedTaskDelta != 0) add("Parked $parkedTaskDelta")
            if (supersededTasksDelta != 0) add("Superseded $supersededTasksDelta")
            if (expiredTasksDelta != 0) add("Expired $expiredTasksDelta")
            if (shiftedLaterCount != 0) add("Shifted $shiftedLaterCount")
            if (sabotageAuctionsTriggered != 0) add("Sabotage $sabotageAuctionsTriggered")
            if (isEmpty()) add("No cascade disruption")
        }.joinToString(" · ")
}

/**
 * Full dry-run result: simulated universe + impact vs baseline.
 */
data class SimulationResult(
    val simulatedState: LifeState,
    val impactReport: SimulationImpactReport,
    val hypotheticalTaskIds: Set<String> = emptySet(),
    val baselineState: LifeState,
)

internal fun countStatus(tasks: List<LifeTask>, status: TaskStatus): Int =
    tasks.count { it.status == status }
