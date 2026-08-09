package com.lookafter.core.notifications

import com.lookafter.core.brain.ExecutiveBrainEngine
import com.lookafter.core.engine.LifeState
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.Medication
import com.lookafter.core.models.TaskStatus
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class NotificationPreferencesTest {

    private val zone = ZoneOffset.UTC
    private val day = LocalDate.of(2026, 8, 8)

    @Test
    fun quietHoursOvernightWindow() {
        val prefs = NotificationPreferences(
            quietHoursEnabled = true,
            quietHoursStartHour = 22,
            quietHoursEndHour = 7,
        )
        val late = day.atTime(23, 0).toInstant(zone)
        val early = day.atTime(3, 0).toInstant(zone)
        val noon = day.atTime(12, 0).toInstant(zone)
        assertTrue(prefs.isInQuietHours(late, zone))
        assertTrue(prefs.isInQuietHours(early, zone))
        assertTrue(!prefs.isInQuietHours(noon, zone))
    }

    @Test
    fun togglesSuppressKinds() {
        val life = LifeState(
            activeTasks = listOf(
                LifeTask(
                    id = "a",
                    title = "Standup",
                    constraintType = ConstraintType.ANCHORED,
                    status = TaskStatus.PENDING,
                    scheduledDate = day,
                    scheduledStart = day.atTime(11, 0).toInstant(zone),
                ),
                LifeTask(id = "b", title = "B", status = TaskStatus.PENDING, scheduledDate = day),
                LifeTask(id = "c", title = "C", status = TaskStatus.PENDING, scheduledDate = day),
                LifeTask(id = "d", title = "D", status = TaskStatus.PENDING, scheduledDate = day),
            ),
            medications = listOf(
                Medication(name = "Mag", scheduledTime = LocalTime.of(8, 0), isTaken = false),
            ),
            currentDay = day,
        )
        val now = day.atTime(10, 0).toInstant(zone)
        val tick = ExecutiveBrainEngine.tick(life, now = now, zone = zone)
        val none = NotificationPolicy.plan(
            life,
            tick.world,
            now = now,
            config = NotificationPolicyConfig(
                medicationsEnabled = false,
                anchoredEnabled = false,
                briefingEnabled = false,
                quietHoursEnabled = false,
            ),
            zone = zone,
        )
        assertEquals(0, none.size)

        val anchoredOnly = NotificationPolicy.plan(
            life,
            tick.world,
            now = now,
            config = NotificationPolicyConfig(
                medicationsEnabled = false,
                anchoredEnabled = true,
                briefingEnabled = false,
                quietHoursEnabled = false,
                anchoredLeadMinutes = 60,
            ),
            zone = zone,
        )
        assertTrue(anchoredOnly.any { it.kind == NotificationKind.ANCHORED_SOON })
    }

    @Test
    fun quietHoursFiltersPlans() {
        val life = LifeState(
            activeTasks = (1..4).map {
                LifeTask(id = "t$it", title = "T$it", status = TaskStatus.PENDING, scheduledDate = day)
            },
            currentDay = day,
        )
        val night = day.atTime(23, 30).toInstant(zone)
        val tick = ExecutiveBrainEngine.tick(life, now = night, zone = zone)
        val plans = NotificationPolicy.plan(
            life,
            tick.world,
            now = night,
            config = NotificationPolicyConfig(
                quietHoursEnabled = true,
                quietHoursStartHour = 22,
                quietHoursEndHour = 7,
                medicationsEnabled = true,
                briefingEnabled = true,
            ),
            zone = zone,
        )
        assertTrue(plans.none { it.kind == NotificationKind.DAILY_BRIEFING })
    }
}
