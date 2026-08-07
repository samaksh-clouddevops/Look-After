package com.lookafter.core.notifications

import com.lookafter.core.brain.ExecutiveBrainEngine
import com.lookafter.core.engine.LifeState
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.TaskStatus
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * Guards the freshness window used by boot reschedule: plans for anchored
 * work in the next day should appear; far-future noise should not dominate.
 */
class NotificationPolicyFreshnessTest {

    @Test
    fun anchoredLeadIsWithinDayWindow() {
        val zone = ZoneOffset.UTC
        val day = LocalDate.of(2026, 8, 7)
        val now = day.atTime(10, 0).toInstant(zone)
        val start = day.atTime(11, 0).toInstant(zone)
        val life = LifeState(
            activeTasks = listOf(
                LifeTask(
                    id = "a1",
                    title = "Client call",
                    constraintType = ConstraintType.ANCHORED,
                    status = TaskStatus.PENDING,
                    scheduledDate = day,
                    scheduledStart = start,
                ),
            ),
        )
        val world = ExecutiveBrainEngine.tick(life, now = now, zone = zone).world
        val plans = NotificationPolicy.plan(life, world, now)
        val anchored = plans.filter { it.kind == NotificationKind.ANCHORED_SOON }
        assertTrue(anchored.isNotEmpty())
        assertTrue(anchored.all { it.fireAt.isAfter(now.minusSeconds(1)) })
        assertTrue(anchored.all { it.fireAt.isBefore(now.plusSeconds(24 * 3600)) })
    }
}
