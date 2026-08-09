package com.lookafter.core.cycle

import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class CycleEngineTest {

    private val start = LocalDate.of(2026, 8, 1)

    @Test
    fun disabledTrackingYieldsNoModifier() {
        val snap = CycleEngine.snapshot(CycleState.EMPTY, today = start)
        assertEquals(false, snap.trackingEnabled)
        assertEquals(0.0, snap.capacityModifier)
        assertEquals(CyclePhase.UNKNOWN, snap.phase)
    }

    @Test
    fun menstrualThenFollicularPhases() {
        var state = CycleEngine.reduce(CycleState.EMPTY, CycleIntent.SetTrackingEnabled(true))
        state = CycleEngine.reduce(state, CycleIntent.SetLastPeriodStart(start))
        state = CycleEngine.reduce(state, CycleIntent.SetPeriodLength(5))
        state = CycleEngine.reduce(state, CycleIntent.SetCycleLength(28))

        val day2 = CycleEngine.snapshot(state, today = start.plusDays(1))
        assertEquals(CyclePhase.MENSTRUAL, day2.phase)
        assertEquals(2, day2.dayInCycle)
        assertTrue(day2.capacityModifier < 0)

        val day10 = CycleEngine.snapshot(state, today = start.plusDays(9))
        assertEquals(CyclePhase.FOLLICULAR, day10.phase)
        assertTrue(day10.capacityModifier > 0)

        val day28 = CycleEngine.snapshot(state, today = start.plusDays(27))
        assertEquals(CyclePhase.LUTEAL, day28.phase)
        assertTrue(day28.capacityModifier < 0)
    }

    @Test
    fun logAndDelete() {
        var state = CycleEngine.reduce(
            CycleState.EMPTY,
            CycleIntent.AddLog(CycleLogEntry(date = start, note = "cramps", isPeriodDay = true)),
        )
        assertEquals(1, state.logs.size)
        val id = state.logs.single().id
        state = CycleEngine.reduce(state, CycleIntent.DeleteLog(id))
        assertTrue(state.logs.isEmpty())
    }
}
