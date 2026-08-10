package com.lookafter.core.behavior

import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class BehaviorEngineTest {

    private val day = LocalDate.of(2026, 8, 10) // Monday

    @Test
    fun addAndToggleCheckInBuildsStreak() {
        var state = BehaviorState.EMPTY
        state = BehaviorEngine.reduce(
            state,
            BehaviorIntent.AddHabit(Habit(id = "h1", title = " Walk ", cadence = HabitCadence.DAILY)),
        )
        assertEquals("Walk", state.habits.single().title)

        state = BehaviorEngine.reduce(state, BehaviorIntent.ToggleCheckIn("h1", day = day.minusDays(1)))
        state = BehaviorEngine.reduce(state, BehaviorIntent.ToggleCheckIn("h1", day = day))
        val h = state.habits.single()
        assertTrue(h.isDoneOn(day))
        assertEquals(2, h.currentStreak)
        assertEquals(2, h.bestStreak)
    }

    @Test
    fun weekdayCadenceSkipsWeekendInStreak() {
        // Friday Aug 7 2026
        val fri = LocalDate.of(2026, 8, 7)
        var h = Habit(id = "h1", title = "Gym", cadence = HabitCadence.WEEKDAYS)
        h = BehaviorEngine.toggleDay(h, fri)
        h = BehaviorEngine.toggleDay(h, fri.minusDays(1)) // Thu
        // As of Monday — streak should walk back skipping Sat/Sun
        h = BehaviorEngine.recomputeStreaks(h, asOf = fri.plusDays(3)) // Mon
        // Not done Mon → streak starts from Fri backward
        assertTrue(h.currentStreak >= 2)
    }

    @Test
    fun undoCheckIn() {
        var h = Habit(id = "h1", title = "Meditate", cadence = HabitCadence.DAILY)
        h = BehaviorEngine.toggleDay(h, day)
        assertTrue(h.isDoneOn(day))
        h = BehaviorEngine.toggleDay(h, day)
        assertTrue(!h.isDoneOn(day))
    }

    @Test
    fun completionRateWindow() {
        var h = Habit(id = "h1", title = "Read", cadence = HabitCadence.DAILY)
        h = BehaviorEngine.toggleDay(h, day)
        h = BehaviorEngine.toggleDay(h, day.minusDays(1))
        val rate = BehaviorEngine.completionRate(h, windowDays = 7, end = day)
        assertTrue(rate > 0.0 && rate <= 1.0)
    }
}
