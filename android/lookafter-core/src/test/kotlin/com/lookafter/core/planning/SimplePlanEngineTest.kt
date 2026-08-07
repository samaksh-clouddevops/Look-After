package com.lookafter.core.planning

import com.lookafter.core.engine.LifeState
import com.lookafter.core.engine.LookAfterIntent
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.Priority
import com.lookafter.core.models.TaskStatus
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class SimplePlanEngineTest {

    @Test
    fun stripParksNonAnchoredLeavingHero() {
        val anchored = LifeTask(
            id = "a",
            title = "Board meeting",
            constraintType = ConstraintType.ANCHORED,
            status = TaskStatus.PENDING,
            priority = Priority.HIGH,
        )
        val fluid = LifeTask(
            id = "f",
            title = "Tidy desk",
            constraintType = ConstraintType.FLUID,
            status = TaskStatus.PENDING,
        )
        val state = LifeState(activeTasks = listOf(fluid, anchored))
        val turn = SimplePlanEngine.interpret("I'm overwhelmed — strip the board", state)
        assertEquals(1, turn.intents.size)
        val park = turn.intents.first() as LookAfterIntent.ParkTask
        assertEquals("f", park.id)
        assertTrue(turn.reply.contains("Board meeting"))
    }

    @Test
    fun parkFluid() {
        val fluid = LifeTask(
            id = "f1",
            title = "Wander",
            constraintType = ConstraintType.FLUID,
            status = TaskStatus.PENDING,
        )
        val flex = LifeTask(
            id = "x1",
            title = "Write",
            constraintType = ConstraintType.FLEXIBLE,
            status = TaskStatus.PENDING,
        )
        val turn = SimplePlanEngine.interpret(
            "park fluid",
            LifeState(activeTasks = listOf(fluid, flex)),
        )
        assertEquals(1, turn.intents.size)
        assertEquals("f1", (turn.intents.first() as LookAfterIntent.ParkTask).id)
    }
}
