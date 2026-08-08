package com.lookafter.core.engine

import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.TaskStatus
import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals

class ReorderAndDayTest {

    private val engine = LifeEngine()

    @Test
    fun reorderTasksSetsSortIndex() {
        val a = LifeTask(id = "a", title = "A", constraintType = ConstraintType.FLEXIBLE, status = TaskStatus.PENDING, sortIndex = 0)
        val b = LifeTask(id = "b", title = "B", constraintType = ConstraintType.FLEXIBLE, status = TaskStatus.PENDING, sortIndex = 1)
        var state = engine.reduce(LifeState.EMPTY, LookAfterIntent.AddTask(a))
        state = engine.reduce(state, LookAfterIntent.AddTask(b))
        state = engine.reduce(state, LookAfterIntent.ReorderTasks(listOf("b", "a")))
        assertEquals(0, state.activeTasks.first { it.id == "b" }.sortIndex)
        assertEquals(1, state.activeTasks.first { it.id == "a" }.sortIndex)
    }

    @Test
    fun setCurrentDay() {
        val day = LocalDate.of(2026, 8, 10)
        val state = engine.reduce(LifeState.EMPTY, LookAfterIntent.SetCurrentDay(day))
        assertEquals(day, state.currentDay)
    }
}
