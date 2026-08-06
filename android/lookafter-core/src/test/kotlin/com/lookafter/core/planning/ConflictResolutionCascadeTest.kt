package com.lookafter.core.planning

import com.lookafter.core.models.ConflictCascadeAction
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.Priority
import com.lookafter.core.models.TemporalBoundingBox
import com.lookafter.core.models.TaskExpirationPolicy
import com.lookafter.core.models.TaskStatus
import java.time.LocalDate
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class ConflictResolutionCascadeTest {

    private val zone = ZoneOffset.UTC
    private val day = LocalDate.of(2026, 3, 11)
    private val now = day.atTime(9, 0).toInstant(zone)

    @Test
    fun `flexible task shifts later past anchored blocker`() {
        val meeting = LifeTask(
            id = "meet",
            title = "Standup",
            durationMinutes = 30,
            constraintType = ConstraintType.ANCHORED,
            priority = Priority.HIGH,
            scheduledDate = day,
            scheduledStart = day.atTime(10, 0).toInstant(zone),
            scheduledEnd = day.atTime(10, 30).toInstant(zone),
        )
        val deepWork = LifeTask(
            id = "deep",
            title = "Deep work",
            durationMinutes = 60,
            constraintType = ConstraintType.FLEXIBLE,
            priority = Priority.MEDIUM,
            expirationPolicy = TaskExpirationPolicy.Infinite,
            scheduledDate = day,
            scheduledStart = day.atTime(10, 0).toInstant(zone),
            scheduledEnd = day.atTime(11, 0).toInstant(zone),
        )

        val result = ConflictResolutionCascade.resolve(
            tasks = listOf(meeting, deepWork),
            day = day,
            now = now,
            zone = zone,
        )

        val shifted = result.tasks.first { it.id == "deep" }
        val kept = result.tasks.first { it.id == "meet" }
        assertEquals(day.atTime(10, 0).toInstant(zone), kept.scheduledStart)
        assertNotNull(shifted.scheduledStart)
        assertTrue(shifted.scheduledStart!! >= day.atTime(10, 35).toInstant(zone))
        assertTrue(
            result.decisions.any {
                it.taskId == "deep" && it.action == ConflictCascadeAction.SHIFT_LATER
            },
        )
    }

    @Test
    fun `flexible shift respects temporal bounding box`() {
        val blocker = LifeTask(
            id = "block",
            title = "Doctor",
            durationMinutes = 60,
            constraintType = ConstraintType.ANCHORED,
            scheduledDate = day,
            scheduledStart = day.atTime(12, 0).toInstant(zone),
            scheduledEnd = day.atTime(13, 0).toInstant(zone),
        )
        val lunch = LifeTask(
            id = "lunch",
            title = "Lunch",
            durationMinutes = 45,
            constraintType = ConstraintType.FLEXIBLE,
            expirationPolicy = TaskExpirationPolicy.EndOfDay,
            temporalBoundingBox = TemporalBoundingBox(earliestStartHour = 11, latestStartHour = 14),
            scheduledDate = day,
            scheduledStart = day.atTime(12, 0).toInstant(zone),
            scheduledEnd = day.atTime(12, 45).toInstant(zone),
        )

        val result = ConflictResolutionCascade.resolve(
            tasks = listOf(blocker, lunch),
            day = day,
            now = now,
            zone = zone,
        )

        val updated = result.tasks.first { it.id == "lunch" }
        // Either shifted inside the box or expired if no valid same-day slot remains.
        val shiftedInsideBox = updated.scheduledStart?.let { start ->
            TemporalBoundingBox(11, 14).contains(start, zone)
        } == true
        val expired = updated.status == TaskStatus.EXPIRED
        assertTrue(shiftedInsideBox || expired, "lunch must shift inside box or expire")
    }

    @Test
    fun `anchored rank beats flexible`() {
        val anchored = LifeTask(
            id = "a",
            title = "A",
            constraintType = ConstraintType.ANCHORED,
            priority = Priority.LOW,
        )
        val flexible = LifeTask(
            id = "f",
            title = "F",
            constraintType = ConstraintType.FLEXIBLE,
            priority = Priority.CRITICAL,
        )
        assertTrue(
            ConflictResolutionCascade.rank(anchored) >
                ConflictResolutionCascade.rank(flexible),
        )
    }
}
