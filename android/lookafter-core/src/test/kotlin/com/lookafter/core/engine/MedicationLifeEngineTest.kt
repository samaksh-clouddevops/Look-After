package com.lookafter.core.engine

import com.lookafter.core.models.Medication
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class MedicationLifeEngineTest {

    private val engine = LifeEngine()

    @Test
    fun addTakeAndDeleteMedication() {
        val med = Medication(
            name = "Magnesium",
            dosage = "200mg",
            scheduledTime = LocalTime.of(8, 0),
        )
        var state = engine.reduce(LifeState.EMPTY, LookAfterIntent.AddMedication(med))
        assertEquals(1, state.medications.size)
        assertFalse(state.medications[0].isTaken)

        state = engine.reduce(
            state,
            LookAfterIntent.TakeMedication(id = med.id, takenAt = Instant.parse("2026-08-07T08:05:00Z"), taken = true),
        )
        assertTrue(state.medications[0].isTaken)
        assertEquals(1, state.medications[0].adherenceLog.size)
        assertEquals(1.0, state.medicationAdherenceRate, 0.001)

        state = engine.reduce(state, LookAfterIntent.DeleteMedication(med.id))
        assertTrue(state.medications.isEmpty())
        assertEquals(0.0, state.medicationAdherenceRate, 0.001)
    }

    @Test
    fun resetMedicationsForNewDayClearsTakenFlags() {
        val med = Medication(name = "Vit D", dosage = "1", isTaken = true)
        var state = engine.reduce(LifeState.EMPTY, LookAfterIntent.AddMedication(med))
        val yesterday = LocalDate.of(2026, 8, 6)
        state = engine.reduce(state, LookAfterIntent.ResetMedicationsForNewDay(yesterday))
        // Same-day re-entry is idempotent after first clear for "today".
        val today = LocalDate.of(2026, 8, 7)
        state = engine.reduce(state, LookAfterIntent.ResetMedicationsForNewDay(today))
        assertFalse(state.medications[0].isTaken)
        assertEquals(today, state.medicationsLastResetDay)

        // Second call same day is a no-op (preserves any later takes).
        state = engine.reduce(
            state,
            LookAfterIntent.TakeMedication(id = med.id, taken = true),
        )
        val again = engine.reduce(state, LookAfterIntent.ResetMedicationsForNewDay(today))
        assertTrue(again.medications[0].isTaken)
    }

    @Test
    fun midnightSweepResetsMedicationFlags() {
        val yesterday = LocalDate.of(2026, 8, 6)
        val today = LocalDate.of(2026, 8, 7)
        val med = Medication(name = "Rx", dosage = "1", isTaken = true)
        val initial = LifeState(
            medications = listOf(med),
            medicationsLastResetDay = yesterday,
            currentDay = yesterday,
        )
        val next = engine.reduce(
            initial,
            LookAfterIntent.TriggerMidnightSweep(
                previousDay = yesterday,
                nextDay = today,
                now = Instant.parse("2026-08-07T00:01:00Z"),
            ),
        )
        assertFalse(next.medications[0].isTaken)
        assertEquals(today, next.medicationsLastResetDay)
        assertEquals(today, next.currentDay)
    }

    @Test
    fun updateMedicationReplacesFields() {
        val med = Medication(name = "Old", dosage = "5mg", scheduledTime = LocalTime.of(9, 0))
        var state = engine.reduce(LifeState.EMPTY, LookAfterIntent.AddMedication(med))
        val updated = med.copy(name = "New", dosage = "10mg", scheduledTime = LocalTime.of(21, 0))
        state = engine.reduce(state, LookAfterIntent.UpdateMedication(updated))
        assertEquals(1, state.medications.size)
        assertEquals("New", state.medications[0].name)
        assertEquals("10mg", state.medications[0].dosage)
        assertEquals(LocalTime.of(21, 0), state.medications[0].scheduledTime)
    }

    @Test
    fun replaceMedicationsBulk() {
        val a = Medication(name = "A")
        val b = Medication(name = "B")
        val state = engine.reduce(
            LifeState.EMPTY,
            LookAfterIntent.ReplaceMedications(listOf(a, b)),
        )
        assertEquals(2, state.medications.size)
        assertNotNull(state.medicationById(a.id))
        assertNotNull(state.medicationById(b.id))
    }
}
