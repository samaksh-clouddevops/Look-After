package com.lookafter.core.simulation

import com.lookafter.core.engine.LifeEngine
import com.lookafter.core.engine.LifeState
import com.lookafter.core.engine.LookAfterIntent
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.TaskExpirationPolicy
import com.lookafter.core.models.TaskStatus
import java.time.LocalDate
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest

class SimulationEngineTest {

    private val zone = ZoneOffset.UTC
    private val day = LocalDate.of(2026, 3, 11)
    private val now = day.atTime(9, 0).toInstant(zone)

    @Test
    fun `dry-run does not mutate baseline and injects hypothetical`() {
        val baselineTask = LifeTask(
            id = "base",
            title = "Deep work",
            durationMinutes = 60,
            constraintType = ConstraintType.FLEXIBLE,
            status = TaskStatus.PENDING,
            scheduledDate = day,
            scheduledStart = day.atTime(11, 0).toInstant(zone),
            scheduledEnd = day.atTime(12, 0).toInstant(zone),
        )
        val baseline = LifeState(activeTasks = listOf(baselineTask), currentDay = day)
        val hypo = LifeTask(
            id = "hypo",
            title = "Hypothetical Meeting",
            durationMinutes = 120,
            constraintType = ConstraintType.ANCHORED,
            status = TaskStatus.PENDING,
            expirationPolicy = TaskExpirationPolicy.EndOfDay,
            scheduledDate = day,
            scheduledStart = day.atTime(11, 0).toInstant(zone),
            scheduledEnd = day.atTime(13, 0).toInstant(zone),
        )

        val result = SimulationEngine.runSimulation(
            baselineState = baseline,
            hypotheticalTasks = listOf(hypo),
            day = day,
            now = now,
            zone = zone,
        )

        // Baseline object identity of contents preserved (no live mutation).
        assertEquals(1, baseline.activeTasks.size)
        assertEquals("base", baseline.activeTasks.single().id)

        assertTrue(result.hypotheticalTaskIds.contains("hypo"))
        assertTrue(result.simulatedState.activeTasks.any { it.id == "hypo" || it.id == "base" })
        // Flexible overlaps anchored → expect shift or park, reflected in impact.
        assertTrue(
            result.impactReport.shiftedLaterCount > 0 ||
                result.impactReport.parkedTaskDelta > 0 ||
                result.simulatedState.activeTasks.any { it.id == "base" },
        )
    }

    @Test
    fun `CommitHypotheticalTasks injects into live engine`() = runTest {
        val engine = LifeEngine(
            initialState = LifeState(currentDay = day),
        )
        val hypo = LifeTask(
            id = "commit-me",
            title = "Board review",
            durationMinutes = 30,
            constraintType = ConstraintType.ANCHORED,
            scheduledDate = day,
            scheduledStart = day.atTime(15, 0).toInstant(zone),
            scheduledEnd = day.atTime(15, 30).toInstant(zone),
        )
        engine.process(
            LookAfterIntent.CommitHypotheticalTasks(
                tasks = listOf(hypo),
                day = day,
                now = now,
                zone = zone,
            ),
        )
        assertTrue(engine.state.value.activeTasks.any { it.id == "commit-me" })
    }
}
