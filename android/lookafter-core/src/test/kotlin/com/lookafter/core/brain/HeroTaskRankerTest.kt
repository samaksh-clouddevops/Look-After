package com.lookafter.core.brain

import com.lookafter.core.engine.LifeState
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.Priority
import com.lookafter.core.models.TaskStatus
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class HeroTaskRankerTest {

    private val zone = ZoneOffset.UTC
    private val day = LocalDate.of(2026, 8, 7)
    private val now = day.atTime(10, 0).toInstant(zone)

    @Test
    fun emptyStateReturnsNullHero() {
        val sel = HeroTaskRanker.select(LifeState.EMPTY, now)
        assertNull(sel.task)
        assertTrue(sel.reason.contains("quiet", ignoreCase = true))
    }

    @Test
    fun prefersAnchoredOverFluid() {
        val fluid = LifeTask(
            id = "f",
            title = "Inbox",
            constraintType = ConstraintType.FLUID,
            status = TaskStatus.PENDING,
            priority = Priority.HIGH,
        )
        val anchored = LifeTask(
            id = "a",
            title = "Standup",
            constraintType = ConstraintType.ANCHORED,
            status = TaskStatus.PENDING,
            priority = Priority.MEDIUM,
            scheduledDate = day,
            scheduledStart = day.atTime(10, 15).toInstant(zone),
            scheduledEnd = day.atTime(10, 30).toInstant(zone),
        )
        val state = LifeState(activeTasks = listOf(fluid, anchored))
        val sel = HeroTaskRanker.select(state, now)
        assertEquals("a", sel.task?.id)
    }

    @Test
    fun prefersInProgress() {
        val pending = LifeTask(
            id = "p",
            title = "Write",
            constraintType = ConstraintType.ANCHORED,
            status = TaskStatus.PENDING,
            scheduledStart = day.atTime(9, 0).toInstant(zone),
        )
        val active = LifeTask(
            id = "ip",
            title = "Deep work",
            constraintType = ConstraintType.FLEXIBLE,
            status = TaskStatus.IN_PROGRESS,
        )
        val sel = HeroTaskRanker.select(
            LifeState(activeTasks = listOf(pending, active)),
            now,
        )
        assertEquals("ip", sel.task?.id)
        assertNotNull(sel.reason)
    }

    @Test
    fun ignoresCompleted() {
        val done = LifeTask(
            id = "d",
            title = "Done",
            status = TaskStatus.COMPLETED,
            constraintType = ConstraintType.ANCHORED,
        )
        val open = LifeTask(
            id = "o",
            title = "Open",
            status = TaskStatus.PENDING,
            constraintType = ConstraintType.FLUID,
        )
        val sel = HeroTaskRanker.select(
            LifeState(activeTasks = listOf(done, open)),
            Instant.parse("2026-08-07T12:00:00Z"),
        )
        assertEquals("o", sel.task?.id)
    }
}
