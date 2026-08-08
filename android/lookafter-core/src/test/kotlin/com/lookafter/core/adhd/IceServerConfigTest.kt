package com.lookafter.core.adhd

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class IceServerConfigTest {

    @Test
    fun defaultsIncludeGoogleStun() {
        val cfg = IceServerConfig()
        assertTrue(cfg.servers.any { it.urls.any { u -> u.contains("stun.l.google.com") } })
        assertEquals(IceServerConfig.IceTransportPolicy.ALL, cfg.iceTransportPolicy)
    }

    @Test
    fun fromTurnAppendsRelayAndOptionalForce() {
        val cfg = IceServerConfig.fromTurn(
            turnUrl = "turn:turn.example.com:3478",
            turnUser = "u",
            turnPass = "p",
            forceRelay = true,
        )
        assertTrue(cfg.servers.any { it.urls.any { u -> u.startsWith("turn:") } })
        assertEquals("u", cfg.servers.last().username)
        assertEquals(IceServerConfig.IceTransportPolicy.RELAY, cfg.iceTransportPolicy)
    }

    @Test
    fun blankTurnKeepsStunOnly() {
        val cfg = IceServerConfig.fromTurn(turnUrl = "  ")
        assertTrue(cfg.servers.none { it.urls.any { u -> u.startsWith("turn:") } })
    }
}
