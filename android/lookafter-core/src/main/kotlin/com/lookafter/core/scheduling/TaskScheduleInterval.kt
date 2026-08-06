package com.lookafter.core.scheduling

import com.lookafter.core.models.LifeTask
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import kotlin.math.max

/**
 * A task's scheduled time window on a specific calendar day.
 * Mirrors iOS `TaskScheduleInterval`.
 */
data class TaskScheduleInterval(
    val taskId: String,
    val start: Instant,
    val end: Instant,
) {
    val durationMinutes: Int
        get() = max(
            Duration.between(start, end).toMinutes().toInt(),
            LifeTask.DEFAULT_MINIMUM_MINUTES,
        )

    fun overlaps(other: TaskScheduleInterval): Boolean =
        start < other.end && other.start < end

    companion object {
        fun window(
            forTask: LifeTask,
            on: LocalDate,
            zone: ZoneId = ZoneOffset.UTC,
        ): TaskScheduleInterval? {
            val scheduledDate = forTask.scheduledDate ?: return null
            if (scheduledDate != on) return null
            val start = forTask.scheduledStart ?: return null

            val duration = max(forTask.durationMinutes, LifeTask.DEFAULT_MINIMUM_MINUTES)
            val end = forTask.scheduledEnd?.takeIf { it > start }
                ?: start.plus(Duration.ofMinutes(duration.toLong()))

            return TaskScheduleInterval(taskId = forTask.id, start = start, end = end)
        }

        fun intervals(
            from: List<LifeTask>,
            on: LocalDate,
            zone: ZoneId = ZoneOffset.UTC,
        ): List<TaskScheduleInterval> =
            from.mapNotNull { window(forTask = it, on = on, zone = zone) }
                .sortedBy { it.start }
    }
}
