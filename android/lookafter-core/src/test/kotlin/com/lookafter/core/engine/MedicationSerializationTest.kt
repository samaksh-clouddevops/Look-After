package com.lookafter.core.engine

import com.lookafter.core.models.Medication
import com.lookafter.core.serialization.LookAfterJson
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class MedicationSerializationTest {

    @Test
    fun lifeStateRoundTripsMedications() {
        val med = Medication(
            id = "med-1",
            name = "Magnesium",
            dosage = "200mg",
            scheduledTime = LocalTime.of(8, 30),
            isTaken = true,
            lastTakenAt = Instant.parse("2026-08-07T08:35:00Z"),
            adherenceLog = listOf(Instant.parse("2026-08-07T08:35:00Z")),
        )
        val state = LifeState(
            medications = listOf(med),
            medicationsLastResetDay = LocalDate.of(2026, 8, 7),
            currentDay = LocalDate.of(2026, 8, 7),
        )
        val json = LookAfterJson.codec.encodeToString(LifeState.serializer(), state)
        val decoded = LookAfterJson.codec.decodeFromString(LifeState.serializer(), json)
        assertEquals(state, decoded)
        assertEquals("Magnesium", decoded.medications.single().name)
        assertEquals(LocalTime.of(8, 30), decoded.medications.single().scheduledTime)
        assertTrue(decoded.medications.single().isTaken)
    }

    @Test
    fun lifeStateDecodesLegacySnapshotWithoutMedicationKeys() {
        // Pre-medication snapshots omit the new fields — defaults must apply.
        val legacy = """{"activeTasks":[],"parkedQueue":[],"somedayVault":[],"actionLogs":[],"consecutiveHighLoadDays":0}"""
        val decoded = LookAfterJson.codec.decodeFromString(LifeState.serializer(), legacy)
        assertTrue(decoded.medications.isEmpty())
        assertEquals(null, decoded.medicationsLastResetDay)
    }
}
