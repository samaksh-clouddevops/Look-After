package com.lookafter.core.execution

import com.lookafter.core.engine.LifeState
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.ExecutionSurfaceMode
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.TaskStatus
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ExecutionBlockResolverTest {

    private val zone = ZoneOffset.UTC
    private val day = LocalDate.of(2026, 3, 11)
    private val now = day.atTime(10, 15).toInstant(zone)

    @Test
    fun `anchored in-window task is focus eligible`() {
        val task = LifeTask(
            id = "a1",
            title = "Standup",
            durationMinutes = 30,
            constraintType = ConstraintType.ANCHORED,
            status = TaskStatus.IN_PROGRESS,
            scheduledDate = day,
            scheduledStart = day.atTime(10, 0).toInstant(zone),
            scheduledEnd = day.atTime(10, 30).toInstant(zone),
        )
        val snap = ExecutionBlockResolver.resolve(
            LifeState(activeTasks = listOf(task), currentDay = day),
            now = now,
        )
        assertTrue(snap.isFocusEligible)
        assertEquals("a1", snap.taskId)
        assertEquals(ExecutionSurfaceMode.ANCHORED, snap.surfaceMode)
        assertTrue(snap.progressFraction in 0.0..1.0)
    }

    @Test
    fun `fluid tasks never own the lock screen`() {
        val fluid = LifeTask(
            id = "f1",
            title = "Wander",
            constraintType = ConstraintType.FLUID,
            status = TaskStatus.PENDING,
            scheduledDate = day,
            scheduledStart = day.atTime(10, 0).toInstant(zone),
            scheduledEnd = day.atTime(11, 0).toInstant(zone),
        )
        val snap = ExecutionBlockResolver.resolve(
            LifeState(activeTasks = listOf(fluid)),
            now = now,
        )
        assertFalse(snap.isFocusEligible)
        assertEquals(ExecutionSurfaceMode.IDLE, snap.surfaceMode)
    }

    @Test
    fun `outside window yields idle`() {
        val task = LifeTask(
            id = "late",
            title = "Later",
            constraintType = ConstraintType.FLEXIBLE,
            status = TaskStatus.PENDING,
            scheduledDate = day,
            scheduledStart = day.atTime(14, 0).toInstant(zone),
            scheduledEnd = day.atTime(15, 0).toInstant(zone),
        )
        val snap = ExecutionBlockResolver.resolve(
            LifeState(activeTasks = listOf(task)),
            now = Instant.parse("2026-03-11T10:00:00Z"),
        )
        assertFalse(snap.isFocusEligible)
    }
}
