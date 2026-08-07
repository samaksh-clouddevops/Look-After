package com.lookafter.core.health

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class HealthSummaryTest {

    @Test
    fun sleepHoursDerivedFromMinutes() {
        val s = HealthSummary(totalSleepMinutes = 450.0)
        assertEquals(7.5, s.sleepHours!!, 0.001)
    }

    @Test
    fun readinessLabels() {
        assertEquals("Peak", HealthSummary(readinessScore = 0.9).readinessLabel)
        assertEquals("Good", HealthSummary(readinessScore = 0.7).readinessLabel)
        assertEquals("Moderate", HealthSummary(readinessScore = 0.5).readinessLabel)
        assertEquals("Low", HealthSummary(readinessScore = 0.3).readinessLabel)
        assertEquals("Recover", HealthSummary(readinessScore = 0.1).readinessLabel)
        assertEquals("Unknown", HealthSummary.EMPTY.readinessLabel)
    }

    @Test
    fun emptyHasNullMetrics() {
        assertNull(HealthSummary.EMPTY.totalSleepMinutes)
        assertNull(HealthSummary.EMPTY.steps)
    }
}
