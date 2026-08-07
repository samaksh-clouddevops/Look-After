package com.lookafter.core.inbox

import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class InboxEngineTest {

    @Test
    fun captureAndPromote() {
        var r = InboxEngine.reduce(InboxState(), InboxIntent.Capture("Call dentist"))
        assertEquals(1, r.state.open.size)
        val id = r.state.open.first().id
        r = InboxEngine.reduce(
            r.state,
            InboxIntent.PromoteToTask(id, durationMinutes = 20, day = LocalDate.of(2026, 8, 7)),
        )
        assertNotNull(r.spawnedTask)
        assertEquals("Call dentist", r.spawnedTask!!.title)
        assertEquals(20, r.spawnedTask!!.durationMinutes)
        assertTrue(r.state.items.first().processed)
        assertTrue(r.state.open.isEmpty())
    }

    @Test
    fun discardRemoves() {
        var r = InboxEngine.reduce(InboxState(), InboxIntent.Capture("x"))
        val id = r.state.open.first().id
        r = InboxEngine.reduce(r.state, InboxIntent.Discard(id))
        assertTrue(r.state.items.isEmpty())
    }

    @Test
    fun emptyCaptureIgnored() {
        val r = InboxEngine.reduce(InboxState(), InboxIntent.Capture("   "))
        assertTrue(r.state.items.isEmpty())
    }
}
