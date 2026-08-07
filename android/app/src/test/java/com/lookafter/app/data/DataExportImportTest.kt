package com.lookafter.app.data

import com.lookafter.core.engine.LifeState
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.TaskStatus
import com.lookafter.core.serialization.LookAfterJson
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
        val json = LookAfterJson.codec.encodeToString(LifeState.serializer(), state)
        val parsed = DataExportImport.parseImport(json).getOrThrow()
        assertEquals(1, parsed.activeTasks.size)
        assertEquals("Write", parsed.activeTasks.first().title)
    }

    @Test
    fun parseImportRejectsGarbage() {
        val result = DataExportImport.parseImport("not-json")
        assertTrue(result.isFailure)
    }

    @Test
    fun prettySummaryListsCounts() {
        val summary = DataExportImport.prettySummary(
            LifeState(activeTasks = listOf(LifeTask(id = "a", title = "A"))),
        )
        assertTrue(summary.contains("active=1"))
    }
}
