package com.lookafter.core.notifications

import com.lookafter.core.brain.ExecutiveBrainEngine
import com.lookafter.core.engine.LifeState
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.Medication
import com.lookafter.core.models.TaskStatus
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertTrue

class NotificationPolicyTest {

    private val zone = ZoneOffset.UTC
    private val day = LocalDate.of(2026, 8, 7)
    private val now = day.atTime(10, 0).toInstant(zone)

    @Test
    fun plansMedicationDue() {
        val life = LifeState(
            medications = listOf(
                Medication(name = "Rx", scheduledTime = LocalTime.of(9, 0), isTaken = false),
            ),
        )
        val world = ExecutiveBrainEngine.tick(life, now = now, zone = zone).world
        val plans = NotificationPolicy.plan(life, world, now)
        assertTrue(plans.any { it.kind == NotificationKind.MEDICATION_DUE })
    }

    @Test
    fun plansAnchoredLead() {
        val start = day.atTime(10, 30).toInstant(zone)
        val life = LifeState(
            activeTasks = listOf(
                LifeTask(
                    id = "a",
                    title = "Standup",
                    constraintType = ConstraintType.ANCHORED,
                    status = TaskStatus.PENDING,
                    scheduledStart = start,
                    scheduledDate = day,
                ),
            ),
        )
        val world = ExecutiveBrainEngine.tick(life, now = now, zone = zone).world
        val plans = NotificationPolicy.plan(life, world, now)
        assertTrue(plans.any { it.kind == NotificationKind.ANCHORED_SOON && it.id.contains("a") })
    }

    @Test
    fun suppressesDuringFocus() {
        val life = LifeState(
            medications = listOf(
                Medication(name = "Rx", scheduledTime = LocalTime.of(9, 0), isTaken = false),
            ),
        )
        val world = ExecutiveBrainEngine.tick(life, now = now, zone = zone).world
        val plans = NotificationPolicy.plan(life, world, now, inFocusSession = true)
        assertTrue(plans.isEmpty())
    }
}
