package com.lookafter.core.execution

import com.lookafter.core.engine.LifeState
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.ExecutionBlockSnapshot
import com.lookafter.core.models.ExecutionSurfaceMode
import com.lookafter.core.models.FocusTaskCategory
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.TaskStatus
import java.time.Duration
import java.time.Instant
import kotlin.math.max
import kotlin.math.min

/**
 * Pure resolver: LifeState + now → current [ExecutionBlockSnapshot].
 * Focus-eligible only for anchored windows and in-window flexible blocks.
 * Mirrors the iOS Live Activity projection surface.
 */
object ExecutionBlockResolver {

    const val FLEXIBLE_CONFIDENCE: Double = 0.85
    const val ANCHORED_CONFIDENCE: Double = 1.0

    fun resolve(
        state: LifeState,
        now: Instant = Instant.now(),
    ): ExecutionBlockSnapshot {
        val candidates = state.activeTasks
            .filter { it.status.isActive && it.scheduledStart != null }
            .mapNotNull { task -> toLiveWindow(task, now) }
            .sortedWith(
                compareByDescending<LiveCandidate> { it.rank }
                    .thenBy { it.windowStart },
            )

        val best = candidates.firstOrNull { it.contains(now) }
            ?: return ExecutionBlockSnapshot.IDLE.copy(generatedAt = now)

        val elapsed = Duration.between(best.windowStart, now).seconds.toDouble()
        val total = max(1.0, Duration.between(best.windowStart, best.windowEnd).seconds.toDouble())
        val progress = min(1.0, max(0.0, elapsed / total))

        val nextUp = state.activeTasks
            .filter {
                it.id != best.task.id &&
                    it.status.isActive &&
                    it.scheduledStart != null &&
                    it.scheduledStart!! >= best.windowEnd
            }
            .minByOrNull { it.scheduledStart!! }
            ?.let { "Next: ${it.title}" }
            .orEmpty()

        return ExecutionBlockSnapshot.clamped(
            id = "exec-${best.task.id}",
            taskId = best.task.id,
            taskTitle = best.task.title,
            category = FocusTaskCategory.DEEP_WORK,
            surfaceMode = best.surfaceMode,
            constraintType = best.task.constraintType,
            windowStart = best.windowStart,
            windowEnd = best.windowEnd,
            progressFraction = progress,
            nextUpSummary = nextUp,
            confidence = best.confidence,
            generatedAt = now,
        )
    }

    private data class LiveCandidate(
        val task: LifeTask,
        val windowStart: Instant,
        val windowEnd: Instant,
        val surfaceMode: ExecutionSurfaceMode,
        val confidence: Double,
        val rank: Int,
    ) {
        fun contains(now: Instant): Boolean = !now.isBefore(windowStart) && now.isBefore(windowEnd)
    }

    private fun toLiveWindow(task: LifeTask, now: Instant): LiveCandidate? {
        val start = task.scheduledStart ?: return null
        val durationMin = max(task.durationMinutes, LifeTask.DEFAULT_MINIMUM_MINUTES)
        val end = task.scheduledEnd?.takeIf { it > start }
            ?: start.plus(Duration.ofMinutes(durationMin.toLong()))

        // Only promote if the window is currently active (or just starting within 1 min grace).
        val graceStart = start.minus(Duration.ofMinutes(1))
        if (now.isBefore(graceStart) || !now.isBefore(end)) return null

        return when (task.constraintType) {
            ConstraintType.ANCHORED -> LiveCandidate(
                task = task,
                windowStart = start,
                windowEnd = end,
                surfaceMode = ExecutionSurfaceMode.ANCHORED,
                confidence = ANCHORED_CONFIDENCE,
                rank = 100,
            )
            ConstraintType.FLEXIBLE -> LiveCandidate(
                task = task,
                windowStart = start,
                windowEnd = end,
                surfaceMode = ExecutionSurfaceMode.FLEXIBLE,
                confidence = FLEXIBLE_CONFIDENCE,
                rank = 50,
            )
            ConstraintType.FLUID -> null // fluid gaps never own the lock screen
        }
    }
}
