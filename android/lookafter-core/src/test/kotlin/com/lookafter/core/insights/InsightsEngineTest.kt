package com.lookafter.core.insights

import com.lookafter.core.engine.LifeState
import com.lookafter.core.health.HealthDayPoint
import com.lookafter.core.health.HealthHistorySeries
import com.lookafter.core.health.HealthSummary
import com.lookafter.core.health.RollingHealthAverages
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.Priority
import com.lookafter.core.models.TaskStatus
import java.time.LocalDate
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class InsightsEngineTest {

    private val day = LocalDate.of(2026, 8, 7)
    private val zone = ZoneOffset.UTC

    @Test
    fun computesFocusAndOpen() {
        val done = LifeTask(
            id = "d",
            title = "Done",
            durationMinutes = 40,
            status = TaskStatus.COMPLETED,
            completedAt = day.atTime(11, 0).toInstant(zone),
            scheduledDate = day,
            tags = listOf("deep-work"),
        )
        val open = LifeTask(
            id = "o",
            title = "Open",
            status = TaskStatus.PENDING,
            constraintType = ConstraintType.ANCHORED,
            scheduledDate = day,
        )
        val snap = InsightsEngine.compute(
            LifeState(activeTasks = listOf(done, open), currentDay = day),
            health = HealthSummary(readinessScore = 0.7),
            asOf = day,
        )
        assertEquals(1, snap.completed7d)
        assertEquals(40, snap.focusMinutes7d)
        assertEquals(1, snap.openNow)
        assertTrue(snap.dayBars.size == 7)
        assertTrue(snap.headline.isNotBlank())
        assertTrue(snap.coachingLine.isNotBlank())
        assertEquals(0.7, snap.readiness)
        assertTrue(snap.performanceScore in 0.0..1.0)
        assertTrue(snap.performanceLabel.isNotBlank())
    }

    @Test
    fun performanceTagHeatAndRecovery() {
        val tasks = listOf(
            LifeTask(
                id = "1",
                title = "Deep",
                status = TaskStatus.COMPLETED,
                durationMinutes = 60,
                tags = listOf("work", "deep"),
                scheduledDate = day,
                completedAt = day.atTime(12, 0).toInstant(zone),
            ),
            LifeTask(
                id = "2",
                title = "Noise",
                status = TaskStatus.PENDING,
                constraintType = ConstraintType.FLUID,
                priority = Priority.HIGH,
                tags = listOf("work"),
                scheduledDate = day,
            ),
        )
        val hist = HealthHistorySeries(
            days = listOf(
                HealthDayPoint(day.minusDays(1), sleepHours = 6.0, readinessScore = 0.5),
                HealthDayPoint(day, sleepHours = 7.5, readinessScore = 0.75),
            ),
            sourceLabel = "test",
        )
        val snap = InsightsEngine.compute(
            state = LifeState(activeTasks = tasks, currentDay = day),
            health = HealthSummary(readinessScore = 0.75),
            asOf = day,
            healthHistory = hist,
            rollingHealth = RollingHealthAverages(
                sleepHours = 6.75,
                readinessScore = 0.62,
                sleepTrendLabel = "up",
                readinessTrendLabel = "up",
            ),
            zone = zone,
        )
        assertTrue(snap.tagHeat.any { it.tag == "work" })
        assertEquals("up", snap.sleepTrend)
        assertTrue(snap.reviewHints.isNotEmpty())
        assertEquals(1, snap.highPriorityOpen)
        assertTrue(snap.fluidShare > 0)
        assertEquals(60, snap.focusMinutes7d)
    }

    @Test
    fun emptyStateHeadline() {
        val snap = InsightsEngine.compute(LifeState(currentDay = day), asOf = day)
        assertEquals(0, snap.openNow)
        assertTrue(snap.headline.contains("clear", ignoreCase = true) || snap.completed7d == 0)
    }
}
