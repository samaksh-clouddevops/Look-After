package com.lookafter.core.health

import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class HealthHistoryEngineTest {

    private val end = LocalDate.of(2026, 8, 8)

    @Test
    fun demoSeriesHasSevenDaysEndingOnTarget() {
        val series = HealthHistoryEngine.demoSeries(endInclusive = end, dayCount = 7)
        assertEquals(7, series.size)
        assertEquals(end, series.last()?.day)
        assertEquals(end.minusDays(6), series.days.first().day)
        assertTrue(series.days.all { it.sleepHours != null && it.readinessScore != null })
        assertEquals("demo", series.sourceLabel)
    }

    @Test
    fun rollingAveragesAndTrends() {
        val rising = HealthHistorySeries(
            days = listOf(
                HealthDayPoint(end.minusDays(2), sleepHours = 5.0, readinessScore = 0.3),
                HealthDayPoint(end.minusDays(1), sleepHours = 6.5, readinessScore = 0.5),
                HealthDayPoint(end, sleepHours = 8.0, readinessScore = 0.8),
            ),
            sourceLabel = "test",
        )
        val avg = HealthHistoryEngine.rollingAverages(rising)
        assertEquals(true, avg.sleepHours != null && avg.sleepHours!! > 6.0)
        assertEquals("up", avg.sleepTrendLabel)
        assertEquals("up", avg.readinessTrendLabel)
    }

    @Test
    fun toSummaryUsesLastDay() {
        val series = HealthHistoryEngine.demoSeries(end, 5)
        val summary = series.toSummary()
        assertEquals(series.last()?.steps, summary.steps)
        assertEquals(series.last()?.readinessScore, summary.readinessScore)
    }
}
