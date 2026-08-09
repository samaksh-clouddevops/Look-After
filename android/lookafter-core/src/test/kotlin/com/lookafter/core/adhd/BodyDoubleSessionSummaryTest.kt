package com.lookafter.core.adhd

import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class BodyDoubleSessionSummaryTest {

    @Test
    fun durationAndPeers() {
        val start = Instant.parse("2026-08-08T10:00:00Z")
        val end = Instant.parse("2026-08-08T10:12:30Z")
        val summary = BodyDoubleSessionSummary.fromSession(
            roomId = "room-x",
            startedAt = start,
            endedAt = end,
            peers = listOf(
                BodyDoublePeer(id = "a", displayName = "You", isLocal = true),
                BodyDoublePeer(id = "b", displayName = "Sam", isConnected = true),
            ),
            webRtcBackend = "native",
            signaling = "firestore",
            reachedConnected = true,
            focusStarted = true,
        )
        assertEquals(12 * 60 + 30, summary.durationSeconds)
        assertTrue(summary.durationLabel.contains("12m"))
        assertEquals(2, summary.peerCount)
        assertTrue(summary.peerNames.contains("Sam"))
        assertTrue(summary.reachedConnected)
        assertTrue(summary.focusStarted)
    }
}
