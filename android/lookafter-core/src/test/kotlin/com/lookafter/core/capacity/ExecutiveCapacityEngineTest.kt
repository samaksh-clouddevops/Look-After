package com.lookafter.core.capacity

import com.lookafter.core.engine.LifeState
import com.lookafter.core.health.HealthSummary
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.TaskStatus
import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ExecutiveCapacityEngineTest {

    private val day = LocalDate.of(2026, 8, 8)

    @Test
    fun lowReadinessShortSleepIsRecoveryOrProtective() {
        val state = LifeState(
            activeTasks = listOf(
                LifeTask(
                    id = "1",
                    title = "Light",
                    durationMinutes = 25,
                    status = TaskStatus.PENDING,
                    scheduledDate = day,
                ),
            ),
            currentDay = day,
        )
        val cap = ExecutiveCapacityEngine.compute(
            state,
            health = HealthSummary(
                readinessScore = 0.28,
                totalSleepMinutes = 4.5 * 60,
            ),
        )
        assertTrue(
            cap.band == CapacityBand.RECOVERY || cap.band == CapacityBand.PROTECTIVE,
            "band=${cap.band}",
        )
        assertTrue(cap.recommendedFocusMinutes <= 60)
        assertTrue(cap.reasons.isNotEmpty())
    }

    @Test
    fun heavyBoardFlagsOverCommitted() {
        val tasks = (1..10).map {
            LifeTask(
                id = "t$it",
                title = "Block $it",
                durationMinutes = 60,
                constraintType = ConstraintType.FLEXIBLE,
                status = TaskStatus.PENDING,
                scheduledDate = day,
            )
        }
        val cap = ExecutiveCapacityEngine.compute(
            LifeState(activeTasks = tasks, currentDay = day),
            health = HealthSummary(readinessScore = 0.8, totalSleepMinutes = 480.0),
        )
        assertTrue(cap.isOverCommitted)
        assertTrue(cap.plannedOpenMinutes >= 600)
    }

    @Test
    fun solidSleepSteadyOrHigh() {
        val cap = ExecutiveCapacityEngine.compute(
            LifeState(currentDay = day),
            health = HealthSummary(readinessScore = 0.82, totalSleepMinutes = 480.0),
        )
        assertTrue(cap.band == CapacityBand.STEADY || cap.band == CapacityBand.HIGH)
        assertEquals(false, cap.isOverCommitted)
    }
}
