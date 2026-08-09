package com.lookafter.core.adhd

import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class RoomSignalCodecTest {

    @Test
    fun encodeDecodeRoundTrip() {
        val env = RoomSignalEnvelope(
            roomId = "room-abc",
            presence = listOf(
                RoomPresence(peerId = "p1", displayName = "Sam", joinedAt = Instant.parse("2026-08-08T10:00:00Z")),
            ),
            signals = listOf(
                BodyDoubleSignal(
                    type = BodyDoubleSignalType.OFFER,
                    fromPeerId = "p1",
                    payload = """{"type":"offer","sdp":"v=0"}""",
                    at = Instant.parse("2026-08-08T10:00:01Z"),
                ),
            ),
            updatedAt = Instant.parse("2026-08-08T10:00:02Z"),
        )
        val raw = RoomSignalCodec.encode(env)
        val decoded = RoomSignalCodec.decode(raw)
        assertTrue(decoded != null)
        assertEquals("room-abc", decoded!!.roomId)
        assertEquals(1, decoded.presence.size)
        assertEquals(BodyDoubleSignalType.OFFER, decoded.signals.single().type)
    }

    @Test
    fun appendSignalAndMarkLeft() {
        var env = RoomSignalEnvelope.empty("r1")
        env = RoomSignalCodec.upsertPresence(
            env,
            RoomPresence(peerId = "a", displayName = "A", joinedAt = Instant.EPOCH),
        )
        env = RoomSignalCodec.appendSignal(
            env,
            BodyDoubleSignal(type = BodyDoubleSignalType.ICE, fromPeerId = "a", payload = "c"),
        )
        assertEquals(1, env.signals.size)
        env = RoomSignalCodec.markLeft(env, "a")
        assertTrue(env.presence.single().left)
        assertTrue(env.signals.any { it.type == BodyDoubleSignalType.HANGUP })
    }
}
