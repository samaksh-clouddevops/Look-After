package com.lookafter.core.brain

import com.lookafter.core.engine.LifeState
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.Priority
import com.lookafter.core.models.TaskStatus
import java.time.Instant

/**
 * Pure local "hero task" selector — first rung of Executive Brain parity
 * without network / LLM. Prefer overdue anchored work, then soonest start,
 * then higher priority / longer blocks.
 */
object HeroTaskRanker {

    data class HeroSelection(
        val task: LifeTask?,
        val reason: String,
    )

    fun select(state: LifeState, now: Instant = Instant.now()): HeroSelection {
        val candidates = state.activeTasks.filter { it.status.isActive }
        if (candidates.isEmpty()) {
            return HeroSelection(null, "Nothing queued — protect the quiet.")
        }

        val scored = candidates.map { task ->
            task to score(task, now)
        }.sortedWith(
            compareByDescending<Pair<LifeTask, Double>> { it.second }
                .thenBy { it.first.scheduledStart ?: Instant.MAX }
                .thenByDescending { it.first.durationMinutes },
        )

        val winner = scored.first().first
        val reason = reasonFor(winner, now)
        return HeroSelection(winner, reason)
    }

    private fun score(task: LifeTask, now: Instant): Double {
        var s = 0.0
        when (task.constraintType) {
            ConstraintType.ANCHORED -> s += 100.0
            ConstraintType.FLEXIBLE -> s += 40.0
            ConstraintType.FLUID -> s += 10.0
        }
        when (task.priority) {
            Priority.CRITICAL, Priority.HIGH -> s += 30.0
            Priority.MEDIUM -> s += 15.0
            Priority.LOW -> s += 5.0
            Priority.SOMEDAY -> s -= 20.0
        }
        if (task.status == TaskStatus.IN_PROGRESS) s += 50.0
        val start = task.scheduledStart
        if (start != null) {
            val minutes = java.time.Duration.between(now, start).toMinutes()
            when {
                minutes < 0 -> s += 80.0 // overdue
                minutes <= 30 -> s += 60.0
                minutes <= 120 -> s += 30.0
                else -> s += 5.0
            }
        }
        if (task.tags.any { it == "capture" }) s -= 5.0
        return s
    }

    private fun reasonFor(task: LifeTask, now: Instant): String {
        val start = task.scheduledStart
        return when {
            task.status == TaskStatus.IN_PROGRESS -> "Already in motion — finish the block."
            task.constraintType == ConstraintType.ANCHORED &&
                start != null && start.isBefore(now) ->
                "Anchored block is overdue — protect the commitment."
            task.constraintType == ConstraintType.ANCHORED ->
                "Next anchored commitment on the board."
            start != null && java.time.Duration.between(now, start).toMinutes() in 0..30 ->
                "Starts within 30 minutes."
            else -> "Highest leverage open task right now."
        }
    }
}
