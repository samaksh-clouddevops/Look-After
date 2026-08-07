package com.lookafter.core.planning

import com.lookafter.core.engine.LifeEngine
import com.lookafter.core.engine.LifeState
import com.lookafter.core.engine.LookAfterIntent
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.TaskStatus
import java.time.LocalDate
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class PlanMutationApplierTest {

    private val zone = ZoneOffset.UTC
    private val day = LocalDate.of(2026, 8, 7)

    @Test
    fun createAndParkApply() {
        val state = LifeState(
            activeTasks = listOf(
                LifeTask(id = "a", title = "Noise", constraintType = ConstraintType.FLUID, status = TaskStatus.PENDING),
            ),
            currentDay = day,
        )
        val proposal = PlanProposal(
            summary = "Park noise + seed block",
            mutations = listOf(
                PlanMutation.ParkTask("a", reason = "test"),
                PlanMutation.CreateTask(
                    title = "Deep work",
                    durationMinutes = 50,
                    day = day.plusDays(1),
                    hour = 9,
                    minute = 0,
                ),
            ),
            dayHorizon = 2,
        )
        val result = PlanMutationApplier.apply(proposal, state, zone)
        assertEquals(2, result.appliedCount)
        assertTrue(result.intents.any { it is LookAfterIntent.ParkTask })
        assertTrue(result.intents.any { it is LookAfterIntent.AddTask })

        val engine = LifeEngine()
        var next = state
        result.intents.forEach { next = engine.reduce(next, it) }
        assertTrue(next.activeTasks.any { it.title == "Deep work" })
        assertTrue(next.parkedQueue.any { it.id == "a" } || next.activeTasks.none { it.id == "a" && it.status.isActive })
    }

    @Test
    fun multiDaySpreadProducesReschedules() {
        val tasks = (1..4).map {
            LifeTask(
                id = "t$it",
                title = "Task $it",
                constraintType = ConstraintType.FLEXIBLE,
                status = TaskStatus.PENDING,
                scheduledDate = day,
            )
        }
        val turn = MultiDayPlanEngine.interpret(
            "spread work across 3 days",
            LifeState(activeTasks = tasks, currentDay = day),
            today = day,
            horizonDays = 3,
        )
        assertEquals(4, turn.proposal.mutations.size)
        assertTrue(turn.proposal.mutations.all { it is PlanMutation.RescheduleTask })
        assertEquals(3, turn.proposal.dayHorizon)
    }
}
