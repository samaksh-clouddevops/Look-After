package com.lookafter.core.adhd

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class BodyDoubleRoomEngineTest {

    @Test
    fun createEntersWaitingWithLocalPeer() {
        val s = BodyDoubleRoomEngine.reduce(
            BodyDoubleRoomState(),
            BodyDoubleRoomIntent.Create(displayName = "Sam"),
        )
        assertEquals(BodyDoubleRoomPhase.WAITING, s.phase)
        assertNotNull(s.roomId)
        assertEquals(1, s.peers.size)
        assertTrue(s.peers.first().isLocal)
        assertEquals("Sam", s.peers.first().displayName)
    }

    @Test
    fun demoConnectReachesConnected() {
        var s = BodyDoubleRoomEngine.reduce(
            BodyDoubleRoomState(),
            BodyDoubleRoomIntent.Create(),
        )
        s = BodyDoubleRoomEngine.demoConnect(s)
        assertEquals(BodyDoubleRoomPhase.CONNECTED, s.phase)
        assertTrue(s.remotePeers.any { it.isConnected })
        assertTrue(s.signals.isNotEmpty())
    }

    @Test
    fun leaveEndsRoom() {
        var s = BodyDoubleRoomEngine.reduce(
            BodyDoubleRoomState(),
            BodyDoubleRoomIntent.Create(),
        )
        s = BodyDoubleRoomEngine.reduce(s, BodyDoubleRoomIntent.Leave)
        assertEquals(BodyDoubleRoomPhase.ENDED, s.phase)
        assertTrue(!s.isActive)
    }
}
