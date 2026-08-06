package com.lookafter.core.planning

import com.lookafter.core.models.ConflictCascadeAction
import com.lookafter.core.models.ConflictCascadeDecision
import com.lookafter.core.models.ConflictCascadeResult
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.TaskExpirationPolicy
import com.lookafter.core.models.TaskStatus
import com.lookafter.core.scheduling.TaskReaper
import com.lookafter.core.scheduling.TaskScheduleInterval
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZoneOffset
import kotlin.math.max

/**
 * Deterministic cascade for overlapping blocks.
 *
 * Priority (high → low): anchored > flexible > fluid, then life commitments,
 * priority, earlier start. Flexible tasks are pushed forward without violating
 * temporal bounding boxes. Pure — returns copies via [LifeTask.copy].
 *
 * Mirrors iOS `ConflictResolutionCascade` (Phase-1: keep / shift / expire / park).
 */
object ConflictResolutionCascade {

    const val DEFAULT_BUFFER_MINUTES: Int = 5
    const val DAY_END_HOUR: Int = 21
    const val MAX_DOMINO_SHIFTS: Int = 2

    fun resolve(
        tasks: List<LifeTask>,
        day: LocalDate,
        now: Instant = Instant.now(),
        zone: ZoneId = ZoneOffset.UTC,
        bufferMinutes: Int = DEFAULT_BUFFER_MINUTES,
    ): ConflictCascadeResult {
        var pool = tasks.filter { isActiveOnDay(it, day) }
        if (pool.size <= 1) return ConflictCascadeResult(tasks = tasks)

        pool = pool.sortedWith(
            compareByDescending<LifeTask> { rank(it) }
                .thenBy {
                    TaskScheduleInterval.window(it, day, zone)?.start ?: Instant.MAX
                },
        )

        val blocked = mutableListOf<TaskScheduleInterval>()
        val decisions = mutableListOf<ConflictCascadeDecision>()
        val changed = linkedSetOf<String>()
        val parkedIds = mutableListOf<String>()
        val byId = tasks.associateBy { it.id }.toMutableMap()
        var shiftCount = 0
        val destinationActives = pool.filter { it.status.isActive }

        for (original in pool) {
            var task = original

            when (
                TaskReaper.verdict(task, now, destinationActives, zone)
            ) {
                TaskReaper.Verdict.EXPIRE -> {
                    task = kill(task, TaskStatus.EXPIRED, now)
                    decisions += decision(task.id, ConflictCascadeAction.EXPIRED, "reaper_expired")
                    changed += task.id
                    byId[task.id] = task
                    continue
                }
                TaskReaper.Verdict.SUPERSEDE -> {
                    task = kill(task, TaskStatus.SUPERSEDED, now)
                    decisions += decision(task.id, ConflictCascadeAction.SUPERSEDED, "semantic_collision")
                    changed += task.id
                    byId[task.id] = task
                    continue
                }
                TaskReaper.Verdict.ALIVE -> Unit
            }

            var interval = TaskScheduleInterval.window(task, day, zone) ?: continue

            if (blocked.none { interval.overlaps(it) }) {
                blocked += interval
                blocked.sortBy { it.start }
                decisions += decision(task.id, ConflictCascadeAction.KEEP, "no_overlap")
                byId[task.id] = task
                continue
            }

            val allowShift = canMove(task) && shiftCount < MAX_DOMINO_SHIFTS
            val policy = task.expirationPolicy

            // Stage 1: shift later same day — capped by temporal bounding box.
            if (allowShift) {
                val open = findOpenStart(
                    durationMinutes = interval.durationMinutes,
                    blocked = blocked,
                    after = interval.start,
                    day = day,
                    bufferMinutes = bufferMinutes,
                    zone = zone,
                )
                if (open != null && TaskReaper.allowsStart(open, task, zone)) {
                    val priorStart = interval.start
                    task = applyStart(task, open, day, zone, now)
                    TaskScheduleInterval.window(task, day, zone)?.let {
                        interval = it
                        blocked += it
                        blocked.sortBy { b -> b.start }
                    }
                    val deltaMin = max(
                        0,
                        Duration.between(priorStart, open).toMinutes().toInt(),
                    )
                    decisions += ConflictCascadeDecision(
                        taskId = task.id,
                        action = ConflictCascadeAction.SHIFT_LATER,
                        reason = "shifted_after_blocker",
                        shiftMinutes = deltaMin,
                    )
                    changed += task.id
                    shiftCount += 1
                    byId[task.id] = task
                    continue
                }
            }

            // Bounding box blocked all same-day shifts → ephemeral kill.
            if (allowShift && task.temporalBoundingBox != null && isEphemeral(policy)) {
                task = kill(task, TaskStatus.EXPIRED, now)
                decisions += decision(task.id, ConflictCascadeAction.EXPIRED, "reaper_outside_bounding_box")
                changed += task.id
                byId[task.id] = task
                continue
            }

            // Ephemeral tasks never park across days.
            if (isEphemeral(policy)) {
                task = kill(task, TaskStatus.EXPIRED, now)
                decisions += decision(task.id, ConflictCascadeAction.EXPIRED, "reaper_no_valid_same_day_slot")
                changed += task.id
                byId[task.id] = task
                continue
            }

            // Anchored overlaps are preserved (shown, not stripped).
            if (task.constraintType == ConstraintType.ANCHORED) {
                blocked += interval
                blocked.sortBy { it.start }
                decisions += decision(task.id, ConflictCascadeAction.KEEP, "anchored_overlap_preserved")
                byId[task.id] = task
                continue
            }

            // Stage 4 (Phase-1): park flexible/fluid.
            task = task.copy(
                scheduledStart = null,
                scheduledEnd = null,
                constraintType = ConstraintType.FLUID,
                updatedAt = now,
            )
            parkedIds += task.id
            decisions += decision(task.id, ConflictCascadeAction.PARK, "parked_to_recovery_queue")
            changed += task.id
            byId[task.id] = task
        }

        val merged = tasks.map { byId[it.id] ?: it }
        val recoveryLock = merged.any {
            "recovery-block" in it.tags || "brain-locked" in it.tags
        }
        return ConflictCascadeResult(
            tasks = merged,
            decisions = decisions,
            changedTaskIds = changed,
            unresolvedTaskIds = emptySet(),
            parkedTaskIds = parkedIds,
            triggeredRecoveryLock = recoveryLock,
        )
    }

    fun rank(task: LifeTask): Int {
        var score = when (task.constraintType) {
            ConstraintType.ANCHORED -> 100
            ConstraintType.FLEXIBLE -> 50
            ConstraintType.FLUID -> 10
        }
        if (task.isLifeCommitment) score += 20
        if (task.constraintType == ConstraintType.ANCHORED && task.scheduledStart != null) {
            score += 15
        }
        score += task.priority.rankBonus
        return score
    }

    fun canMove(task: LifeTask): Boolean = when (task.constraintType) {
        ConstraintType.ANCHORED -> false
        ConstraintType.FLEXIBLE, ConstraintType.FLUID -> true
    }

    private fun isEphemeral(policy: TaskExpirationPolicy): Boolean = when (policy) {
        is TaskExpirationPolicy.EndOfDay, is TaskExpirationPolicy.StrictWindow -> true
        is TaskExpirationPolicy.Infinite -> false
    }

    private fun isActiveOnDay(task: LifeTask, day: LocalDate): Boolean =
        task.status.isActive && task.scheduledStart != null && task.scheduledDate == day

    private fun kill(task: LifeTask, status: TaskStatus, now: Instant): LifeTask =
        task.copy(
            status = status,
            scheduledStart = null,
            scheduledEnd = null,
            updatedAt = now,
        )

    private fun decision(
        taskId: String,
        action: ConflictCascadeAction,
        reason: String,
    ): ConflictCascadeDecision = ConflictCascadeDecision(taskId, action, reason)

    private fun applyStart(
        task: LifeTask,
        start: Instant,
        day: LocalDate,
        zone: ZoneId,
        now: Instant,
    ): LifeTask {
        val duration = max(task.durationMinutes, LifeTask.DEFAULT_MINIMUM_MINUTES)
        val end = start.plus(Duration.ofMinutes(duration.toLong()))
        return task.copy(
            scheduledDate = day,
            scheduledStart = start,
            scheduledEnd = end,
            updatedAt = now,
        )
    }

    private fun findOpenStart(
        durationMinutes: Int,
        blocked: List<TaskScheduleInterval>,
        after: Instant,
        day: LocalDate,
        bufferMinutes: Int,
        zone: ZoneId,
    ): Instant? {
        val dayEnd = day.atTime(LocalTime.of(DAY_END_HOUR, 0)).atZone(zone).toInstant()
        val buffer = Duration.ofMinutes(bufferMinutes.toLong())
        val seeds = listOf(after) + blocked.map { it.end.plus(buffer) }
        for (seed in seeds) {
            var candidate = maxInstant(seed, after)
            repeat(96) {
                val probeEnd = candidate.plus(Duration.ofMinutes(durationMinutes.toLong()))
                if (probeEnd > dayEnd) return@repeat
                val overlap = blocked.firstOrNull { candidate < it.end && it.start < probeEnd }
                if (overlap == null) return candidate
                candidate = overlap.end.plus(buffer)
            }
        }
        return null
    }

    private fun maxInstant(a: Instant, b: Instant): Instant = if (a >= b) a else b
}
