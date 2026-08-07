package com.lookafter.core.simulation

import com.lookafter.core.engine.LifeState
import com.lookafter.core.models.CascadeActionKind
import com.lookafter.core.models.ConflictCascadeAction
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.TaskStatus
import com.lookafter.core.planning.ConflictResolutionCascade
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset

/**
 * Pure what-if planner. Never touches parked queues / cascade logs of the live engine.
 * Deep-copies baseline, injects hypotheticals, dry-runs the cascade, diffs impact.
 */
object SimulationEngine {

    const val HYPOTHETICAL_TAG: String = "hypothetical"

    fun runSimulation(
        baselineState: LifeState,
        hypotheticalTasks: List<LifeTask>,
        day: LocalDate? = null,
        now: Instant = Instant.now(),
        zone: ZoneId = ZoneOffset.UTC,
        bufferMinutes: Int = ConflictResolutionCascade.DEFAULT_BUFFER_MINUTES,
    ): SimulationResult {
        val taggedHypotheticals = hypotheticalTasks.map { task ->
            task.copy(tags = (task.tags + HYPOTHETICAL_TAG).distinct())
        }
        val hypoIds = taggedHypotheticals.map { it.id }.toSet()

        // Deep copy via list copies — LifeTask is immutable data class.
        val combinedActive = baselineState.activeTasks + taggedHypotheticals
        val sandbox = baselineState.copy(
            activeTasks = combinedActive,
            // Dry-run must not pollute baseline action log semantics; start fresh for diffing cascade.
            actionLogs = baselineState.actionLogs,
        )

        val resolveDay = day
            ?: sandbox.currentDay
            ?: taggedHypotheticals.firstNotNullOfOrNull { it.scheduledDate }
            ?: baselineState.activeTasks.firstNotNullOfOrNull { it.scheduledDate }
            ?: LocalDate.ofInstant(now, zone)

        val cascade = ConflictResolutionCascade.resolve(
            tasks = sandbox.activeTasks,
            day = resolveDay,
            now = now,
            zone = zone,
            bufferMinutes = bufferMinutes,
        )

        val parkedIds = cascade.parkedTaskIds.toSet()
        val stillActive = cascade.tasks.filterNot { it.id in parkedIds }
        val newlyParked = cascade.tasks
            .filter { it.id in parkedIds }
            .map {
                it.copy(
                    constraintType = ConstraintType.FLUID,
                    tags = (it.tags + "parked").distinct(),
                )
            }

        val simulated = sandbox.copy(
            activeTasks = stillActive,
            parkedQueue = sandbox.parkedQueue + newlyParked,
            currentDay = resolveDay,
            // Projected streak bump when cascade parks 2+ or shifts thrash heavily.
            consecutiveHighLoadDays = projectedStreak(
                baseline = sandbox.consecutiveHighLoadDays,
                parkedDelta = newlyParked.size,
                shiftCount = cascade.decisions.count {
                    it.action == ConflictCascadeAction.SHIFT_LATER
                },
            ),
        )

        val report = diffImpact(
            baseline = baselineState,
            simulated = simulated,
            decisions = cascade.decisions,
        )

        return SimulationResult(
            simulatedState = simulated,
            impactReport = report,
            hypotheticalTaskIds = hypoIds,
            baselineState = baselineState,
        )
    }

    private fun projectedStreak(baseline: Int, parkedDelta: Int, shiftCount: Int): Int {
        val pressure = parkedDelta + if (shiftCount >= 2) 1 else 0
        return if (pressure >= 2) baseline + 1 else baseline
    }

    private fun diffImpact(
        baseline: LifeState,
        simulated: LifeState,
        decisions: List<com.lookafter.core.models.ConflictCascadeDecision>,
    ): SimulationImpactReport {
        val baseParked = baseline.parkedQueue.size
        val simParked = simulated.parkedQueue.size
        val baseSuperseded = countStatus(baseline.activeTasks, TaskStatus.SUPERSEDED) +
            countStatus(baseline.parkedQueue, TaskStatus.SUPERSEDED)
        val simSuperseded = countStatus(simulated.activeTasks, TaskStatus.SUPERSEDED) +
            countStatus(simulated.parkedQueue, TaskStatus.SUPERSEDED)
        val baseExpired = countStatus(baseline.activeTasks, TaskStatus.EXPIRED)
        val simExpired = countStatus(simulated.activeTasks, TaskStatus.EXPIRED)

        val shifted = decisions.count { it.action == ConflictCascadeAction.SHIFT_LATER }
        // Sabotage is a recovery-lock side effect — detect via tags left by cascade recovery lock.
        val sabotage = if (simulated.triggeredRecoveryHint()) 1 else 0

        return SimulationImpactReport(
            parkedTaskDelta = (simParked - baseParked).coerceAtLeast(0),
            sabotageAuctionsTriggered = sabotage,
            supersededTasksDelta = (simSuperseded - baseSuperseded).coerceAtLeast(0),
            expiredTasksDelta = (simExpired - baseExpired).coerceAtLeast(0),
            highLoadStreakDelta =
                (simulated.consecutiveHighLoadDays - baseline.consecutiveHighLoadDays)
                    .coerceAtLeast(0),
            activeTaskDelta = simulated.activeTasks.size - baseline.activeTasks.size,
            shiftedLaterCount = shifted,
        )
    }

    private fun LifeState.triggeredRecoveryHint(): Boolean =
        activeTasks.any { "recovery-block" in it.tags || "brain-locked" in it.tags } ||
            parkedQueue.any { "recovery-block" in it.tags || "brain-locked" in it.tags }
}
