package com.lookafter.app.brain

import com.lookafter.core.engine.LifeState
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest

class HttpLlmCoachConfigTest {

    @Test
    fun blankKeyIsNotConfigured() {
        val coach = HttpLlmCoachService(apiKey = "")
        assertFalse(coach.isConfigured)
    }

    @Test
    fun blankKeyReturnsEmptySoFallbackCanRun() = runTest {
        val coach = HttpLlmCoachService(apiKey = "   ".trim())
        val reply = coach.reply("hello", LifeState.EMPTY)
        assertEquals("", reply)
    }

    @Test
    fun configuredWhenKeyPresent() {
        val coach = HttpLlmCoachService(apiKey = "sk-test")
        assertTrue(coach.isConfigured)
    }
}
