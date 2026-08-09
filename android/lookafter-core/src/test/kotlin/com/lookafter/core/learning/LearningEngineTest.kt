package com.lookafter.core.learning

import java.time.Instant
import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class LearningEngineTest {

    private val day = LocalDate.of(2026, 8, 8)
    private val now = Instant.parse("2026-08-08T12:00:00Z")

    @Test
    fun addTrackAndCardDueToday() {
        var state = LearningState.EMPTY
        state = LearningEngine.reduce(
            state,
            LearningIntent.AddTrack(LearningTrack(id = "t1", title = " Spanish ", createdAt = now)),
        )
        assertEquals("Spanish", state.tracks.single().title)
        state = LearningEngine.reduce(
            state,
            LearningIntent.AddCard(
                LearningCard(id = "c1", front = "hola", back = "hello", dueOn = day, createdAt = now),
                trackId = "t1",
            ),
        )
        assertEquals(1, state.dueCards(day, "t1").size)
        assertEquals("hola", state.dueCards(day).single().front)
    }

    @Test
    fun goodReviewAdvancesInterval() {
        val card = LearningCard(id = "c1", front = "x", dueOn = day, intervalDays = 0, repetitions = 0)
        val next = LearningEngine.applyReview(card, ReviewGrade.GOOD, today = day, now = now)
        assertEquals(1, next.intervalDays)
        assertEquals(1, next.repetitions)
        assertEquals(day.plusDays(1), next.dueOn)

        val second = LearningEngine.applyReview(next, ReviewGrade.GOOD, today = day.plusDays(1), now = now)
        assertEquals(3, second.intervalDays)
    }

    @Test
    fun againResets() {
        val card = LearningCard(
            id = "c1",
            front = "x",
            dueOn = day,
            intervalDays = 10,
            repetitions = 4,
            easeFactor = 2.5,
        )
        val next = LearningEngine.applyReview(card, ReviewGrade.AGAIN, today = day, now = now)
        assertEquals(0, next.repetitions)
        assertEquals(0, next.intervalDays)
        assertTrue(next.easeFactor < 2.5)
        assertEquals(day, next.dueOn)
    }
}
