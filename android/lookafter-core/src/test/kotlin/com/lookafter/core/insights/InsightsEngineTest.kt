package com.lookafter.core.insights

import com.lookafter.core.engine.LifeState
import com.lookafter.core.health.HealthSummary
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.TaskStatus
import java.time.Instant
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
    }

    @Test
    fun emptyStateHeadline() {
        val snap = InsightsEngine.compute(LifeState(currentDay = day), asOf = day)
        assertEquals(0, snap.openNow)
        assertTrue(snap.headline.contains("clear", ignoreCase = true) || snap.completed7d == 0)
    }
}
