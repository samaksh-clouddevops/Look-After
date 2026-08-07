package com.lookafter.core.engine

import com.lookafter.core.models.CascadeActionKind
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.TaskExpirationPolicy
import com.lookafter.core.models.TaskStatus
import java.time.LocalDate
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest

class LifeEngineTest {

    private val zone = ZoneOffset.UTC
    private val yesterday = LocalDate.of(2026, 3, 10)
    private val today = LocalDate.of(2026, 3, 11)
    private val now = today.atTime(0, 5).toInstant(zone)

    @Test
    fun `TriggerMidnightSweep expires EndOfDay tasks and emits new state`() = runTest {
        val ephemeral = LifeTask(
            id = "eod-meal",
            title = "Dinner",
            durationMinutes = 45,
            constraintType = ConstraintType.FLEXIBLE,
            status = TaskStatus.PENDING,
            expirationPolicy = TaskExpirationPolicy.EndOfDay,
            scheduledDate = yesterday,
            scheduledStart = yesterday.atTime(19, 0).toInstant(zone),
            scheduledEnd = yesterday.atTime(19, 45).toInstant(zone),
        )
        val keeper = LifeTask(
            id = "deep-work",
            title = "Write spec",
            durationMinutes = 90,
            status = TaskStatus.PENDING,
            expirationPolicy = TaskExpirationPolicy.Infinite,
            scheduledDate = yesterday,
            scheduledStart = yesterday.atTime(14, 0).toInstant(zone),
        )

        val engine = LifeEngine(
            initialState = LifeState(
                activeTasks = listOf(ephemeral, keeper),
                currentDay = yesterday,
            ),
        )

        engine.process(
            LookAfterIntent.TriggerMidnightSweep(
                previousDay = yesterday,
                nextDay = today,
                now = now,
                zone = zone,
            ),
        )

        val state = engine.state.value
        val meal = state.activeTasks.first { it.id == "eod-meal" }
        val work = state.taskById("deep-work")!!

        assertEquals(TaskStatus.EXPIRED, meal.status)
        assertEquals(null, meal.scheduledStart)
        // Infinite work is parked for rollover, not expired.
        assertTrue(
            work.status == TaskStatus.PENDING &&
                (work.id in state.parkedQueue.map { it.id } || work.scheduledDate == null),
            "infinite incomplete should be parked/cleared, not left scheduled on yesterday",
        )
        assertEquals(today, state.currentDay)
        assertTrue(state.actionLogs.any { it.action == CascadeActionKind.EXPIRED && it.taskId == "eod-meal" })
        assertTrue(state.actionLogs.isNotEmpty())
    }

    @Test
    fun `AddTask and DeleteTask update active pool`() = runTest {
        val engine = LifeEngine()
        val task = LifeTask(id = "t1", title = "Inbox zero")
        engine.process(LookAfterIntent.AddTask(task))
        assertEquals(1, engine.state.value.activeTasks.size)
        engine.process(LookAfterIntent.DeleteTask(task.id))
        assertEquals(0, engine.state.value.activeTasks.size)
    }

    @Test
    fun `RunCascadeReconciliation shifts flexible past anchored`() = runTest {
        val day = today
        val meeting = LifeTask(
            id = "meet",
            title = "Standup",
            durationMinutes = 30,
            constraintType = ConstraintType.ANCHORED,
            scheduledDate = day,
            scheduledStart = day.atTime(10, 0).toInstant(zone),
            scheduledEnd = day.atTime(10, 30).toInstant(zone),
        )
        val deep = LifeTask(
            id = "deep",
            title = "Deep work",
            durationMinutes = 60,
            constraintType = ConstraintType.FLEXIBLE,
            expirationPolicy = TaskExpirationPolicy.Infinite,
            scheduledDate = day,
            scheduledStart = day.atTime(10, 0).toInstant(zone),
            scheduledEnd = day.atTime(11, 0).toInstant(zone),
        )
        val engine = LifeEngine(LifeState(activeTasks = listOf(meeting, deep), currentDay = day))

        engine.process(
            LookAfterIntent.RunCascadeReconciliation(day = day, now = now, zone = zone),
        )

        val shifted = engine.state.value.activeTasks.first { it.id == "deep" }
        assertTrue(shifted.scheduledStart!! >= day.atTime(10, 35).toInstant(zone))
        assertTrue(engine.state.value.actionLogs.any { it.action == CascadeActionKind.SHIFTED_LATER })
    }

    @Test
    fun `CompleteTask marks task completed and logs focus`() = runTest {
        val task = LifeTask(id = "c1", title = "Ship UI", durationMinutes = 45)
        val engine = LifeEngine(LifeState(activeTasks = listOf(task)))
        engine.process(LookAfterIntent.CompleteTask(id = "c1", completedAt = now))
        val done = engine.state.value.activeTasks.single()
        assertEquals(TaskStatus.COMPLETED, done.status)
        assertEquals(now, done.completedAt)
        assertTrue(
            engine.state.value.actionLogs.any {
                it.action == CascadeActionKind.FOCUS_COMPLETED && it.focusMinutes == 45
            },
        )
    }
}
