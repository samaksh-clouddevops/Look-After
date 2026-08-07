package com.lookafter.core.adhd

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class BodyDoublingPromptsTest {

    @Test
    fun rotatesOverTime() {
        val a = BodyDoublingPrompts.lineFor(0)
        val b = BodyDoublingPrompts.lineFor(45)
        assertNotEquals(a, b)
    }

    @Test
    fun emergencyUsesDifferentPool() {
        val normal = BodyDoublingPrompts.lineFor(0, emergencyMode = false)
        val emergency = BodyDoublingPrompts.lineFor(0, emergencyMode = true)
        assertTrue(emergency.lowercase().contains("emergency") || emergency.lowercase().contains("10"))
        assertNotEquals(normal, emergency)
    }

    @Test
    fun stableForSameOffset() {
        assertEquals(
            BodyDoublingPrompts.lineFor(90, emergencyMode = true),
            BodyDoublingPrompts.lineFor(90, emergencyMode = true),
        )
    }

    @Test
    fun poolsNonEmpty() {
        assertTrue(BodyDoublingPrompts.poolSize(false) >= 4)
        assertTrue(BodyDoublingPrompts.poolSize(true) >= 4)
    }
}
