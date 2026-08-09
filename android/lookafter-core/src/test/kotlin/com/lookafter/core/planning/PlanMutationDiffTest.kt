package com.lookafter.core.planning

import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.Priority
import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class PlanMutationDiffTest {

    @Test
    fun describesCreateAndPark() {
        val proposal = PlanProposal(
            summary = "Lighten week",
            dayHorizon = 3,
            mutations = listOf(
                PlanMutation.CreateTask(
                    title = "Deep work",
                    durationMinutes = 50,
                    constraint = ConstraintType.FLEXIBLE,
                    priority = Priority.HIGH,
                    day = LocalDate.of(2026, 8, 9),
                    hour = 9,
                    minute = 0,
                ),
                PlanMutation.ParkTask("task-abc", reason = "noise"),
            ),
        )
        val lines = PlanMutationDiff.lines(proposal)
        assertEquals(2, lines.size)
        assertEquals("Create", lines[0].kind)
        assertTrue(lines[0].summary.contains("Deep work"))
        assertTrue(lines[0].detail.contains("50m"))
        assertEquals("Park", lines[1].kind)
        val headline = PlanMutationDiff.headline(proposal)
        assertTrue(headline.contains("Lighten") || headline.contains("3d"))
    }

    @Test
    fun horizonIntentKeepsPreferenceOnClear() {
        var state = PlanningConversationState(horizonDays = 7)
        state = PlanningConversationEngine.reduce(
            state,
            PlanningConversationIntent.SetHorizonDays(3),
        ).state
        assertEquals(3, state.horizonDays)
        state = PlanningConversationEngine.reduce(
            state,
            PlanningConversationIntent.UserMessage("hello"),
        ).state
        state = PlanningConversationEngine.reduce(
            state,
            PlanningConversationIntent.Clear,
        ).state
        assertEquals(3, state.horizonDays)
        assertTrue(state.messages.isEmpty())
    }

    @Test
    fun offlineTurnHonorsHorizon() {
        val life = com.lookafter.core.engine.LifeState(
            activeTasks = (1..4).map {
                com.lookafter.core.models.LifeTask(
                    id = "t$it",
                    title = "Task $it",
                    constraintType = ConstraintType.FLEXIBLE,
                    status = com.lookafter.core.models.TaskStatus.PENDING,
                    scheduledDate = LocalDate.of(2026, 8, 8),
                )
            },
            currentDay = LocalDate.of(2026, 8, 8),
        )
        val (proposal, _) = PlanningConversationEngine.offlineTurn(
            message = "spread work across the week",
            life = life,
            horizonDays = 7,
        )
        if (proposal.mutations.isNotEmpty()) {
            assertEquals(7, proposal.dayHorizon)
        }
    }
}
