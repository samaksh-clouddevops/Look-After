package com.lookafter.core.adhd

import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class FocusSessionEngineTest {

    private val t0 = Instant.parse("2026-08-07T10:00:00Z")

    @Test
    fun startPauseResumeComplete() {
        var s = FocusSessionState()
        s = FocusSessionEngine.reduce(
            s,
            FocusSessionIntent.Start(
                taskId = "t1",
                taskTitle = "Write",
                plannedMinutes = 25,
                now = t0,
            ),
        )
        assertEquals(FocusSessionPhase.RUNNING, s.phase)
        assertEquals(25 * 60L, s.remainingSeconds(t0))

        val t1 = t0.plusSeconds(300)
        s = FocusSessionEngine.reduce(s, FocusSessionIntent.Pause(t1))
        assertEquals(FocusSessionPhase.PAUSED, s.phase)
        assertEquals(300, s.accumulatedActiveSeconds)

        val t2 = t1.plusSeconds(60)
        s = FocusSessionEngine.reduce(s, FocusSessionIntent.Resume(t2))
        assertEquals(FocusSessionPhase.RUNNING, s.phase)

        s = FocusSessionEngine.reduce(s, FocusSessionIntent.Complete(t2.plusSeconds(100)))
        assertEquals(FocusSessionPhase.COMPLETED, s.phase)
        assertTrue(s.accumulatedActiveSeconds >= 400)
    }

    @Test
    fun tickAutoCompletesWhenTimeUp() {
        var s = FocusSessionEngine.reduce(
            FocusSessionState(),
            FocusSessionIntent.Start("t", "Block", plannedMinutes = 1, now = t0),
        )
        s = FocusSessionEngine.reduce(s, FocusSessionIntent.Tick(t0.plusSeconds(61)))
        assertEquals(FocusSessionPhase.COMPLETED, s.phase)
    }

    @Test
    fun abortEndsSession() {
        var s = FocusSessionEngine.reduce(
            FocusSessionState(),
            FocusSessionIntent.Start("t", "Block", now = t0),
        )
        s = FocusSessionEngine.reduce(s, FocusSessionIntent.Abort(t0.plusSeconds(10)))
        assertEquals(FocusSessionPhase.ABORTED, s.phase)
    }
}
