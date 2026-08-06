package com.lookafter.core.planning

import com.lookafter.core.models.ConflictCascadeAction
import com.lookafter.core.models.ConflictCascadeDecision
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.DayReconcileResult
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.TaskExpirationPolicy
import com.lookafter.core.models.TaskStatus
import com.lookafter.core.scheduling.TaskReaper
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset

/**
 * Day-boundary Reaper + same-day reconcile entry points.
 *
 * Pure functions over immutable [LifeTask] lists — returns copies via [LifeTask.copy].
 * Mirrors iOS `DayScheduleReconciler` Stage-0 ephemerality layer.
 */
object DayScheduleReconciler {

    /**
     * Midnight / day-boundary Reaper sweep.
     *
     * - [TaskExpirationPolicy.EndOfDay] incomplete → [TaskStatus.EXPIRED]
     *   (Phase-1 contract; iOS uses `.skipped` with cascade action `.expired` —
     *   Android Phase-1 unifies on EXPIRED per physics-port spec.)
     * - [SemanticCollisionStrategy.DROP_OLDEST] with matching [LifeTask.semanticHash]
     *   already active today → [TaskStatus.SUPERSEDED]
     * - [TaskExpirationPolicy.StrictWindow] miss → EXPIRED
     * - recurrence occurrences → SUPERSEDED (series refresh)
     * - otherwise park as fluid + clear schedule for rollover
     */
    fun sweepDayBoundary(
        tasks: List<LifeTask>,
        previousDay: LocalDate,
        nextDay: LocalDate,
        now: Instant = Instant.now(),
        zone: ZoneId = ZoneOffset.UTC,
    ): DayReconcileResult {
        val tomorrowActives = tasks.filter { task ->
            task.status.isActive && task.scheduledDate == nextDay
        }

        val changed = linkedSetOf<String>()
        val decisions = mutableListOf<ConflictCascadeDecision>()
        val byId = tasks.associateBy { it.id }.toMutableMap()

        val yesterdayIncomplete = tasks.filter { task ->
            task.status.isActive && task.scheduledDate == previousDay
        }

        for (original in yesterdayIncomplete) {
            var task = original
            when (val policy = task.expirationPolicy) {
                is TaskExpirationPolicy.EndOfDay -> {
                    task = task.copy(
                        status = TaskStatus.EXPIRED,
                        scheduledStart = null,
                        scheduledEnd = null,
                        updatedAt = now,
                    )
                    byId[task.id] = task
                    changed += task.id
                    decisions += ConflictCascadeDecision(
                        taskId = task.id,
                        action = ConflictCascadeAction.EXPIRED,
                        reason = "midnight_end_of_day",
                    )
                    continue
                }
                is TaskExpirationPolicy.StrictWindow -> {
                    val start = task.scheduledStart
                    if (start != null && now > start.plus(Duration.ofMinutes(policy.minutes.toLong()))) {
                        task = task.copy(
                            status = TaskStatus.EXPIRED,
                            scheduledStart = null,
                            scheduledEnd = null,
                            updatedAt = now,
                        )
                        byId[task.id] = task
                        changed += task.id
                        decisions += ConflictCascadeDecision(
                            taskId = task.id,
                            action = ConflictCascadeAction.EXPIRED,
                            reason = "midnight_strict_window",
                        )
                        continue
                    }
                }
                is TaskExpirationPolicy.Infinite -> Unit
            }

            when (
                TaskReaper.verdict(
                    task = task,
                    now = now,
                    destinationDayTasks = tomorrowActives,
                    zone = zone,
                )
            ) {
                TaskReaper.Verdict.SUPERSEDE -> {
                    task = task.copy(
                        status = TaskStatus.SUPERSEDED,
                        scheduledStart = null,
                        scheduledEnd = null,
                        updatedAt = now,
                    )
                    byId[task.id] = task
                    changed += task.id
                    decisions += ConflictCascadeDecision(
                        taskId = task.id,
                        action = ConflictCascadeAction.SUPERSEDED,
                        reason = "midnight_semantic_collision",
                    )
                    continue
                }
                TaskReaper.Verdict.EXPIRE -> {
                    task = task.copy(
                        status = TaskStatus.EXPIRED,
                        scheduledStart = null,
                        scheduledEnd = null,
                        updatedAt = now,
                    )
                    byId[task.id] = task
                    changed += task.id
                    decisions += ConflictCascadeDecision(
                        taskId = task.id,
                        action = ConflictCascadeAction.EXPIRED,
                        reason = "midnight_reaper_expire",
                    )
                    continue
                }
                TaskReaper.Verdict.ALIVE -> Unit
            }

            // Recurrence occurrences are re-materialized on sync — never park stale series rows.
            if (task.parentTaskId != null) {
                task = task.copy(
                    status = TaskStatus.SUPERSEDED,
                    scheduledStart = null,
                    scheduledEnd = null,
                    updatedAt = now,
                )
                byId[task.id] = task
                changed += task.id
                decisions += ConflictCascadeDecision(
                    taskId = task.id,
                    action = ConflictCascadeAction.SUPERSEDED,
                    reason = "midnight_series_refresh",
                )
                continue
            }

            // Park for rollover as fluid / unscheduled.
            task = task.copy(
                scheduledStart = null,
                scheduledEnd = null,
                scheduledDate = null,
                constraintType = ConstraintType.FLUID,
                updatedAt = now,
            )
            byId[task.id] = task
            changed += task.id
            decisions += ConflictCascadeDecision(
                taskId = task.id,
                action = ConflictCascadeAction.PARK,
                reason = "midnight_park_for_rollover",
            )
        }

        val merged = tasks.map { byId[it.id] ?: it }
        return DayReconcileResult(
            tasks = merged,
            changedTaskIds = changed,
            conflictTaskIds = emptySet(),
            decisions = decisions,
        )
    }

    /**
     * Convenience: reconcile a single day by running the cascade only.
     * LifeModel commitment snapping is intentionally out of Phase-1 scope.
     */
    fun reconcile(
        tasks: List<LifeTask>,
        day: LocalDate,
        now: Instant = Instant.now(),
        zone: ZoneId = ZoneOffset.UTC,
        bufferMinutes: Int = ConflictResolutionCascade.DEFAULT_BUFFER_MINUTES,
    ): DayReconcileResult {
        val cascade = ConflictResolutionCascade.resolve(
            tasks = tasks,
            day = day,
            now = now,
            zone = zone,
            bufferMinutes = bufferMinutes,
        )
        return DayReconcileResult(
            tasks = cascade.tasks,
            changedTaskIds = cascade.changedTaskIds,
            conflictTaskIds = emptySet(),
            decisions = cascade.decisions,
        )
    }
}
