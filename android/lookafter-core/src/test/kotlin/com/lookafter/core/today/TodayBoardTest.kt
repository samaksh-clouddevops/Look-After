package com.lookafter.core.today

import com.lookafter.core.engine.LifeState
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.Medication
import com.lookafter.core.models.Priority
import com.lookafter.core.models.TaskStatus
import java.time.LocalDate
import java.time.LocalTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class TodayBoardTest {

    private val day = LocalDate.of(2026, 8, 8)

    @Test
    fun sectionsGroupByConstraintAndStatus() {
        val tasks = listOf(
            task("a", ConstraintType.ANCHORED, TaskStatus.PENDING),
            task("f", ConstraintType.FLEXIBLE, TaskStatus.PENDING),
            task("u", ConstraintType.FLUID, TaskStatus.PENDING),
            task("ip", ConstraintType.FLEXIBLE, TaskStatus.IN_PROGRESS),
            task("d", ConstraintType.FLUID, TaskStatus.COMPLETED),
        )
        val sections = TodayBoard.sections(tasks, TodayFilter.ALL)
        assertTrue(sections.any { it.kind == TodaySectionKind.IN_PROGRESS && it.count == 1 })
        assertTrue(sections.any { it.kind == TodaySectionKind.ANCHORED && it.count == 1 })
        assertTrue(sections.any { it.kind == TodaySectionKind.FLEXIBLE && it.count == 1 })
        assertTrue(sections.any { it.kind == TodaySectionKind.FLUID && it.count == 1 })
        assertTrue(sections.any { it.kind == TodaySectionKind.COMPLETED && it.count == 1 })
    }

    @Test
    fun filterAnchoredOnly() {
        val tasks = listOf(
            task("a", ConstraintType.ANCHORED, TaskStatus.PENDING),
            task("f", ConstraintType.FLEXIBLE, TaskStatus.PENDING),
        )
        val sections = TodayBoard.sections(tasks, TodayFilter.ANCHORED)
        assertEquals(1, sections.size)
        assertEquals(TodaySectionKind.ANCHORED, sections.first().kind)
        assertEquals("a", sections.first().tasks.single().id)
    }

    @Test
    fun loadSummaryLabels() {
        val light = TodayBoard.loadSummary(
            listOf(task("a", ConstraintType.FLUID, TaskStatus.PENDING, minutes = 20)),
        )
        assertEquals("Light", light.loadLabel)
        assertEquals(1, light.openCount)

        val heavyTasks = (1..8).map {
            task("t$it", ConstraintType.FLEXIBLE, TaskStatus.PENDING, minutes = 60)
        }
        val heavy = TodayBoard.loadSummary(heavyTasks)
        assertEquals("Heavy", heavy.loadLabel)
    }

    @Test
    fun medsStripDueFlags() {
        val meds = listOf(
            Medication(id = "1", name = "AM", scheduledTime = LocalTime.of(8, 0), isTaken = false),
            Medication(id = "2", name = "PM", scheduledTime = LocalTime.of(20, 0), isTaken = false),
        )
        val strip = TodayBoard.medsStrip(meds, now = LocalTime.of(10, 0))
        assertTrue(strip.first { it.id == "1" }.isDue)
        assertTrue(!strip.first { it.id == "2" }.isDue)
    }

    @Test
    fun dayTasksIncludesUndated() {
        val state = LifeState(
            activeTasks = listOf(
                task("today", ConstraintType.FLEXIBLE, TaskStatus.PENDING).copy(scheduledDate = day),
                task("inbox", ConstraintType.FLUID, TaskStatus.PENDING).copy(scheduledDate = null),
                task("other", ConstraintType.FLUID, TaskStatus.PENDING).copy(scheduledDate = day.plusDays(1)),
            ),
            currentDay = day,
        )
        val board = TodayBoard.dayTasks(state, day)
        assertEquals(setOf("today", "inbox"), board.map { it.id }.toSet())
    }

    private fun task(
        id: String,
        c: ConstraintType,
        status: TaskStatus,
        minutes: Int = 30,
        priority: Priority = Priority.MEDIUM,
    ) = LifeTask(
        id = id,
        title = id,
        durationMinutes = minutes,
        constraintType = c,
        status = status,
        priority = priority,
        scheduledDate = day,
    )
}
