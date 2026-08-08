package com.lookafter.core.planning

import com.lookafter.core.engine.LifeEngine
import com.lookafter.core.engine.LifeState
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.TaskStatus
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class PlanningConversationEngineTest {

    @Test
    fun offerThenAcceptAppliesMutations() {
        val task = LifeTask(
            id = "f1",
            title = "Fluid noise",
            constraintType = ConstraintType.FLUID,
            status = TaskStatus.PENDING,
        )
        val life = LifeState(activeTasks = listOf(task))
        var conv = PlanningConversationState()
        conv = PlanningConversationEngine.reduce(
            conv,
            PlanningConversationIntent.UserMessage("park fluid"),
        ).state
        val proposal = PlanProposal(
            summary = "Park fluid",
            mutations = listOf(PlanMutation.ParkTask("f1", reason = "test")),
        )
        conv = PlanningConversationEngine.reduce(
            conv,
            PlanningConversationIntent.OfferPlan(
                proposal = proposal,
                reply = "Parking fluid work.",
                sourceLabel = "offline",
            ),
        ).state
        assertNotNull(conv.pending)
        assertEquals(1, conv.pending!!.proposal.mutations.size)

        val intents = PlanningConversationEngine.intentsForPending(conv.pending!!, life)
        assertEquals(1, intents.size)
        val engine = LifeEngine()
        var next = life
        intents.forEach { next = engine.reduce(next, it) }
        assertTrue(next.parkedQueue.any { it.id == "f1" } || next.activeTasks.none { it.id == "f1" && it.status.isActive })

        conv = PlanningConversationEngine.reduce(conv, PlanningConversationIntent.AcceptPending).state
        assertEquals(true, conv.pending?.accepted)
        assertTrue(conv.messages.any { it.text.contains("Applied") })
    }

    @Test
    fun rejectClearsWithoutRequireApply() {
        var conv = PlanningConversationState()
        conv = PlanningConversationEngine.reduce(
            conv,
            PlanningConversationIntent.OfferPlan(
                proposal = PlanProposal(
                    summary = "x",
                    mutations = listOf(PlanMutation.DeleteTask("nope")),
                ),
                reply = "Delete?",
                sourceLabel = "test",
            ),
        ).state
        conv = PlanningConversationEngine.reduce(conv, PlanningConversationIntent.RejectPending).state
        assertEquals(false, conv.pending?.accepted)
        assertTrue(conv.messages.any { it.text.contains("discarded", ignoreCase = true) })
    }

    @Test
    fun offerWithoutMutationsDoesNotPend() {
        val conv = PlanningConversationEngine.reduce(
            PlanningConversationState(),
            PlanningConversationIntent.OfferPlan(
                proposal = PlanProposal(summary = "Nothing to do"),
                reply = "Board clear",
                sourceLabel = "offline",
            ),
        ).state
        assertNull(conv.pending)
    }
}
