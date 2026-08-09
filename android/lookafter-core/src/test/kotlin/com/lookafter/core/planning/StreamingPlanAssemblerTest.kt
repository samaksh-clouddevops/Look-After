package com.lookafter.core.planning

import com.lookafter.core.models.ConstraintType
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class StreamingPlanAssemblerTest {

    @Test
    fun bracesBalancedDetectsIncompleteJson() {
        assertTrue(!StreamingPlanAssembler.bracesBalanced("""{"summary":"x","mutations":["""))
        assertTrue(StreamingPlanAssembler.bracesBalanced("""{"summary":"x","mutations":[]}"""))
        assertTrue(!StreamingPlanAssembler.bracesBalanced("""not json"""))
    }

    @Test
    fun progressiveParseWaitsUntilBalanced() {
        val asm = StreamingPlanAssembler()
        asm.append("""{"summary":"Lighten","dayHorizon":3,"mutations":[""")
        val mid = asm.tryParse(streamFinished = false)
        assertTrue(mid is StreamingPlanAssembler.ParseAttempt.Partial)

        asm.append(
            """{"type":"parkTask","taskId":"t1","reason":"plan"}]}""",
        )
        val done = asm.tryParse(streamFinished = true)
        assertTrue(done is StreamingPlanAssembler.ParseAttempt.Success)
        val proposal = (done as StreamingPlanAssembler.ParseAttempt.Success).proposal
        assertEquals(1, proposal.mutations.size)
        assertTrue(proposal.mutations.first() is PlanMutation.ParkTask)
    }

    @Test
    fun stripsMarkdownFencesOnComplete() {
        val inner = PlanProposalJson.encode(
            PlanProposal(
                summary = "ok",
                dayHorizon = 2,
                mutations = listOf(
                    PlanMutation.CreateTask(
                        title = "Deep work",
                        durationMinutes = 50,
                        constraint = ConstraintType.FLEXIBLE,
                    ),
                ),
            ),
        )
        val fenced = "```json\n$inner\n```"
        val proposal = StreamingPlanAssembler.parseComplete(fenced)
        assertTrue(proposal != null)
        assertEquals(1, proposal!!.mutations.size)
        assertEquals("ok", proposal.summary)
    }

    @Test
    fun invalidJsonFinishedIsFailed() {
        val asm = StreamingPlanAssembler()
        asm.append("not-a-plan")
        val attempt = asm.tryParse(streamFinished = true)
        assertTrue(attempt is StreamingPlanAssembler.ParseAttempt.Failed)
    }

    @Test
    fun emptyBuffer() {
        assertTrue(
            StreamingPlanAssembler().tryParse(streamFinished = true)
                is StreamingPlanAssembler.ParseAttempt.Empty,
        )
    }
}
