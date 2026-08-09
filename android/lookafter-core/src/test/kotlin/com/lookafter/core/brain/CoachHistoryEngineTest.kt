package com.lookafter.core.brain

import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class CoachHistoryEngineTest {

    @Test
    fun pinSurvivesClearUnpinned() {
        var state = CoachHistoryState.EMPTY
        val hero = CoachHistoryEngine.fromHeroDecision(
            BrainDecision(heroTitle = "Deep work", reason = "Anchored next", coachLine = "Go."),
            now = Instant.parse("2026-08-08T10:00:00Z"),
        )
        state = CoachHistoryEngine.reduce(state, CoachHistoryIntent.Record(hero))
        val pinnedId = state.entries.first().id
        state = CoachHistoryEngine.reduce(state, CoachHistoryIntent.Pin(pinnedId, true))
        state = CoachHistoryEngine.reduce(
            state,
            CoachHistoryIntent.Record(CoachHistoryEngine.fromCoachReply("hello")),
        )
        assertEquals(2, state.entries.size)
        state = CoachHistoryEngine.reduce(state, CoachHistoryIntent.ClearUnpinned)
        assertEquals(1, state.entries.size)
        assertTrue(state.entries.single().pinned)
        assertEquals("Deep work", state.entries.single().title)
    }

    @Test
    fun planOutcomeKinds() {
        val accepted = CoachHistoryEngine.fromPlanOutcome(true, "Lighten week", 3)
        val discarded = CoachHistoryEngine.fromPlanOutcome(false, "No", 0)
        assertEquals(CoachHistoryKind.PLAN_ACCEPTED, accepted.kind)
        assertEquals(CoachHistoryKind.PLAN_DISCARDED, discarded.kind)
        assertTrue(accepted.body.contains("3"))
    }

    @Test
    fun heroBodyIncludesWhy() {
        val entry = CoachHistoryEngine.fromHeroDecision(
            BrainDecision(
                heroTaskId = "t1",
                heroTitle = "Write",
                reason = "Highest rank",
                coachLine = "Protect buffers.",
            ),
            world = WorldState(capacityBand = com.lookafter.core.capacity.CapacityBand.PROTECTIVE),
        )
        assertEquals(CoachHistoryKind.HERO_DECISION, entry.kind)
        assertTrue(entry.body.contains("Highest rank"))
        assertTrue(entry.body.contains("Protect buffers"))
        assertTrue(entry.body.contains("Protective") || entry.body.contains("capacity"))
    }

    @Test
    fun clearAll() {
        var state = CoachHistoryEngine.reduce(
            CoachHistoryState.EMPTY,
            CoachHistoryIntent.Record(CoachHistoryEngine.fromCoachReply("x")),
        )
        state = CoachHistoryEngine.reduce(state, CoachHistoryIntent.ClearAll)
        assertTrue(state.entries.isEmpty())
    }
}
