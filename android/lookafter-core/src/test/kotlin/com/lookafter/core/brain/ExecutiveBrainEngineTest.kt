package com.lookafter.core.brain

import com.lookafter.core.engine.LifeState
import com.lookafter.core.health.HealthSummary
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.Medication
import com.lookafter.core.models.TaskStatus
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class ExecutiveBrainEngineTest {

    private val zone = ZoneOffset.UTC
    private val day = LocalDate.of(2026, 8, 7)
    private val now = day.atTime(10, 0).toInstant(zone)

    @Test
    fun tickBuildsWorldAndDecision() {
        val task = LifeTask(
            id = "t1",
            title = "Deep work",
            constraintType = ConstraintType.ANCHORED,
            status = TaskStatus.PENDING,
            scheduledDate = day,
            scheduledStart = day.atTime(10, 30).toInstant(zone),
        )
        val tick = ExecutiveBrainEngine.tick(
            life = LifeState(activeTasks = listOf(task), currentDay = day),
            health = HealthSummary(readinessScore = 0.8, totalSleepMinutes = 450.0),
            now = now,
            zone = zone,
        )
        assertEquals("t1", tick.decision.heroTaskId)
        assertEquals("Deep work", tick.decision.heroTitle)
        assertTrue(tick.world.healthReadiness >= 0.8)
        assertEquals(SleepQuality.EXCELLENT, tick.world.sleepQuality)
        assertTrue(tick.decision.coachLine.isNotBlank())
    }

    @Test
    fun medicationDueSurfacesInWorld() {
        val med = Medication(
            name = "Mag",
            scheduledTime = LocalTime.of(9, 0),
            isTaken = false,
        )
        val tick = ExecutiveBrainEngine.tick(
            life = LifeState(medications = listOf(med)),
            now = now,
            zone = zone,
        )
        assertTrue(tick.world.medicationStatus is MedicationWorldStatus.DueNow)
    }

    @Test
    fun coachReplyHandlesOverwhelmAndMeds() {
        val life = LifeState(
            activeTasks = List(6) {
                LifeTask(id = "t$it", title = "Task $it", status = TaskStatus.PENDING)
            },
            medications = listOf(
                Medication(name = "Rx", scheduledTime = LocalTime.of(8, 0), isTaken = false),
            ),
        )
        val overwhelm = ExecutiveBrainEngine.coachReply("I'm overwhelmed", life, now = now)
        assertTrue(overwhelm.lowercase().contains("strip") || overwhelm.lowercase().contains("load"))
        val med = ExecutiveBrainEngine.coachReply("meds?", life, now = now)
        assertTrue(med.contains("Rx"))
    }

    @Test
    fun emptyStateCoachIsCalm() {
        val tick = ExecutiveBrainEngine.tick(LifeState.EMPTY, now = now, zone = zone)
        assertEquals(null, tick.decision.heroTaskId)
        assertNotNull(tick.decision.coachLine)
    }
}
