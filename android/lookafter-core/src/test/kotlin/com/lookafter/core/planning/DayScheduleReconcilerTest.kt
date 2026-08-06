package com.lookafter.core.planning

import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.SemanticCollisionStrategy
import com.lookafter.core.models.TaskExpirationPolicy
import com.lookafter.core.models.TaskStatus
import java.time.LocalDate
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class DayScheduleReconcilerTest {

    private val zone = ZoneOffset.UTC
    private val yesterday = LocalDate.of(2026, 3, 10)
    private val today = LocalDate.of(2026, 3, 11)
    private val now = today.atTime(8, 0).toInstant(zone)

    @Test
    fun `endOfDay incomplete tasks expire at midnight boundary`() {
        val stale = LifeTask(
            id = "eod-1",
            title = "Evening stretch",
            durationMinutes = 20,
            constraintType = ConstraintType.FLEXIBLE,
            status = TaskStatus.PENDING,
            expirationPolicy = TaskExpirationPolicy.EndOfDay,
            scheduledDate = yesterday,
            scheduledStart = yesterday.atTime(19, 0).toInstant(zone),
        )

        val result = DayScheduleReconciler.sweepDayBoundary(
            tasks = listOf(stale),
            previousDay = yesterday,
            nextDay = today,
            now = now,
            zone = zone,
        )

        val updated = result.tasks.single()
        assertEquals(TaskStatus.EXPIRED, updated.status)
        assertEquals(null, updated.scheduledStart)
        assertTrue("eod-1" in result.changedTaskIds)
    }

    @Test
    fun `dropOldest collision supersedes yesterday when today has same semanticHash`() {
        val hash = "physicalActivity|session"
        val yesterdayGym = LifeTask(
            id = "gym-old",
            title = "Push day",
            durationMinutes = 60,
            status = TaskStatus.PENDING,
            semanticHash = hash,
            expirationPolicy = TaskExpirationPolicy.Infinite,
            collisionStrategy = SemanticCollisionStrategy.DROP_OLDEST,
            scheduledDate = yesterday,
            scheduledStart = yesterday.atTime(17, 0).toInstant(zone),
        )
        val todayGym = LifeTask(
            id = "gym-new",
            title = "Pull day",
            durationMinutes = 60,
            status = TaskStatus.PENDING,
            semanticHash = hash,
            collisionStrategy = SemanticCollisionStrategy.DROP_OLDEST,
            scheduledDate = today,
            scheduledStart = today.atTime(17, 0).toInstant(zone),
        )

        val result = DayScheduleReconciler.sweepDayBoundary(
            tasks = listOf(yesterdayGym, todayGym),
            previousDay = yesterday,
            nextDay = today,
            now = now,
            zone = zone,
        )

        val old = result.tasks.first { it.id == "gym-old" }
        val neu = result.tasks.first { it.id == "gym-new" }
        assertEquals(TaskStatus.SUPERSEDED, old.status)
        assertEquals(TaskStatus.PENDING, neu.status)
    }

    @Test
    fun `infinite tasks without collision are parked as fluid`() {
        val work = LifeTask(
            id = "work-1",
            title = "Write report",
            durationMinutes = 90,
            status = TaskStatus.PENDING,
            expirationPolicy = TaskExpirationPolicy.Infinite,
            collisionStrategy = SemanticCollisionStrategy.ALLOW_MULTIPLE,
            scheduledDate = yesterday,
            scheduledStart = yesterday.atTime(14, 0).toInstant(zone),
            scheduledEnd = yesterday.atTime(15, 30).toInstant(zone),
        )

        val result = DayScheduleReconciler.sweepDayBoundary(
            tasks = listOf(work),
            previousDay = yesterday,
            nextDay = today,
            now = now,
            zone = zone,
        )

        val updated = result.tasks.single()
        assertEquals(TaskStatus.PENDING, updated.status)
        assertEquals(ConstraintType.FLUID, updated.constraintType)
        assertEquals(null, updated.scheduledDate)
        assertEquals(null, updated.scheduledStart)
    }
}
