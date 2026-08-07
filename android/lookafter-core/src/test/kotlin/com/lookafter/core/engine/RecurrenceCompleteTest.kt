package com.lookafter.core.engine

import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.RecurrenceRule
import com.lookafter.core.models.TaskStatus
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class RecurrenceCompleteTest {

    private val engine = LifeEngine()
    private val zone = ZoneOffset.UTC
    private val day = LocalDate.of(2026, 8, 7) // Friday
    private val now = day.atTime(10, 0).toInstant(zone)

    @Test
    fun dailySpawnsNextDayOnComplete() {
        val task = recurring("Daily stretch", RecurrenceRule.DAILY, day)
        var state = engine.reduce(LifeState.EMPTY, LookAfterIntent.AddTask(task))
        state = engine.reduce(state, LookAfterIntent.CompleteTask(task.id, now))
        assertEquals(TaskStatus.COMPLETED, state.taskById(task.id)?.status)
        val next = state.activeTasks.firstOrNull { it.parentTaskId == task.id }
        assertNotNull(next)
        assertEquals(day.plusDays(1), next.scheduledDate)
        assertEquals(TaskStatus.PENDING, next.status)
        assertTrue(next.tags.contains("recurrence"))
    }

    @Test
    fun weekdaysSkipsWeekend() {
        val friday = day
        val task = recurring("Standup", RecurrenceRule.WEEKDAYS, friday)
        var state = engine.reduce(LifeState.EMPTY, LookAfterIntent.AddTask(task))
        state = engine.reduce(state, LookAfterIntent.CompleteTask(task.id, now))
        val next = state.activeTasks.first { it.parentTaskId == task.id }
        // Friday → Monday
        assertEquals(LocalDate.of(2026, 8, 10), next.scheduledDate)
    }

    @Test
    fun noneDoesNotSpawn() {
        val task = recurring("Once", RecurrenceRule.NONE, day)
        var state = engine.reduce(LifeState.EMPTY, LookAfterIntent.AddTask(task))
        state = engine.reduce(state, LookAfterIntent.CompleteTask(task.id, now))
        assertTrue(state.activeTasks.none { it.parentTaskId == task.id })
        assertEquals(1, state.activeTasks.count { it.id == task.id })
    }

    private fun recurring(title: String, rule: RecurrenceRule, on: LocalDate): LifeTask {
        val start = on.atTime(LocalTime.of(9, 0)).toInstant(zone)
        return LifeTask(
            id = "t-$title",
            title = title,
            durationMinutes = 25,
            constraintType = ConstraintType.FLEXIBLE,
            status = TaskStatus.PENDING,
            scheduledDate = on,
            scheduledStart = start,
            scheduledEnd = start.plusSeconds(25 * 60),
            recurrence = rule,
        )
    }
}
