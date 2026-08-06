package com.lookafter.core.scheduling

import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.SemanticCollisionStrategy
import com.lookafter.core.models.TaskExpirationPolicy
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset

/**
 * Stage 0 ephemerality verdicts — expire / supersede before cascade moves.
 * Mirrors iOS `TaskReaper`.
 */
object TaskReaper {

    enum class Verdict {
        ALIVE,
        EXPIRE,
        SUPERSEDE,
    }

    fun verdict(
        task: LifeTask,
        now: Instant = Instant.now(),
        destinationDayTasks: List<LifeTask> = emptyList(),
        zone: ZoneId = ZoneOffset.UTC,
    ): Verdict {
        when (val policy = task.expirationPolicy) {
            is TaskExpirationPolicy.Infinite -> Unit
            is TaskExpirationPolicy.EndOfDay -> {
                val scheduledDate = task.scheduledDate
                if (scheduledDate != null) {
                    val today = LocalDate.ofInstant(now, zone)
                    if (scheduledDate.isBefore(today)) return Verdict.EXPIRE
                }
            }
            is TaskExpirationPolicy.StrictWindow -> {
                val start = task.scheduledStart
                if (start != null) {
                    val deadline = start.plus(Duration.ofMinutes(policy.minutes.toLong()))
                    if (now > deadline) return Verdict.EXPIRE
                }
            }
        }

        if (task.collisionStrategy == SemanticCollisionStrategy.DROP_OLDEST) {
            val key = collisionKey(task)
            val hasDup = destinationDayTasks.any {
                it.id != task.id && it.status.isActive && collisionKey(it) == key
            }
            if (hasDup) return Verdict.SUPERSEDE
        }

        return Verdict.ALIVE
    }

    fun collisionKey(task: LifeTask): String =
        task.semanticHash.ifBlank { "task|${task.id}" }

    fun allowsStart(
        start: Instant,
        task: LifeTask,
        zone: ZoneId = ZoneOffset.UTC,
    ): Boolean {
        val box = task.temporalBoundingBox ?: return true
        return box.contains(start, zone)
    }
}
