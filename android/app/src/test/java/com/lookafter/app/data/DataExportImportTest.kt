package com.lookafter.app.data

import com.lookafter.core.engine.LifeState
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.Medication
import com.lookafter.core.models.TaskStatus
import com.lookafter.core.serialization.LookAfterJson
import java.time.LocalDate
import java.time.LocalTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class DataExportImportTest {

    @Test
    fun parseImportRoundTrip() {
        val state = LifeState(
            activeTasks = listOf(
                LifeTask(id = "1", title = "Write", status = TaskStatus.PENDING),
            ),
        )
        val json = DataExportImport.encode(state)
        val parsed = DataExportImport.parseImport(json).getOrThrow()
        assertEquals(1, parsed.activeTasks.size)
        assertEquals("Write", parsed.activeTasks.first().title)
    }

    @Test
    fun encodeIncludesMedicationsAndDay() {
        val state = LifeState(
            medications = listOf(
                Medication(id = "m1", name = "Mag", dosage = "1", scheduledTime = LocalTime.of(8, 0)),
            ),
            currentDay = LocalDate.of(2026, 8, 7),
        )
        val json = DataExportImport.encode(state)
        assertTrue(json.contains("Mag"))
        assertTrue(json.contains("2026-08-07"))
        val parsed = DataExportImport.parseImport(json).getOrThrow()
        assertEquals(1, parsed.medications.size)
        assertEquals(LocalDate.of(2026, 8, 7), parsed.currentDay)
    }

    @Test
    fun parseImportRejectsGarbage() {
        val result = DataExportImport.parseImport("not-json")
        assertTrue(result.isFailure)
    }

    @Test
    fun parseImportTrimsWhitespace() {
        val state = LifeState(activeTasks = listOf(LifeTask(id = "x", title = "X")))
        val json = "\n\n" + DataExportImport.encode(state) + "\n"
        val parsed = DataExportImport.parseImport(json).getOrThrow()
        assertEquals("X", parsed.activeTasks.single().title)
    }

    @Test
    fun prettySummaryListsCounts() {
        val summary = DataExportImport.prettySummary(
            LifeState(activeTasks = listOf(LifeTask(id = "a", title = "A"))),
        )
        assertTrue(summary.contains("active=1"))
        assertTrue(summary.contains("meds=0"))
    }
}
