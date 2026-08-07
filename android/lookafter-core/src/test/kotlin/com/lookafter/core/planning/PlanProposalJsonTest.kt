package com.lookafter.core.planning

import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.Priority
import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class PlanProposalJsonTest {

    @Test
    fun roundTripCreateAndPark() {
        val proposal = PlanProposal(
            summary = "Lighten Friday",
            dayHorizon = 2,
            mutations = listOf(
                PlanMutation.ParkTask(taskId = "t1", reason = "plan"),
                PlanMutation.CreateTask(
                    title = "Deep work",
                    durationMinutes = 50,
                    constraint = ConstraintType.FLEXIBLE,
                    priority = Priority.HIGH,
                    day = LocalDate.of(2026, 8, 8),
                    hour = 9,
                    minute = 0,
                ),
            ),
        )
        val raw = PlanProposalJson.encode(proposal)
        val decoded = PlanProposalJson.decode(raw)
        assertNotNull(decoded)
        assertEquals(2, decoded.mutations.size)
        assertEquals("Lighten Friday", decoded.summary)
        assertTrue(decoded.mutations[0] is PlanMutation.ParkTask)
        assertTrue(decoded.mutations[1] is PlanMutation.CreateTask)
    }

    @Test
    fun stripsMarkdownFences() {
        val inner = PlanProposalJson.encode(
            PlanProposal(
                summary = "ok",
                mutations = listOf(PlanMutation.DeleteTask("x")),
            ),
        )
        val fenced = "```json\n$inner\n```"
        val decoded = PlanProposalJson.decode(fenced)
        assertNotNull(decoded)
        assertEquals(1, decoded.mutations.size)
    }
}
