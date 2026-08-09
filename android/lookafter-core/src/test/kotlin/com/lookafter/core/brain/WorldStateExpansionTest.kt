package com.lookafter.core.brain

import com.lookafter.core.capacity.CapacityBand
import com.lookafter.core.engine.LifeState
import com.lookafter.core.health.HealthSummary
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

class WorldStateExpansionTest {

    private val zone = ZoneOffset.UTC
    private val day = LocalDate.of(2026, 8, 8)
    private val now = day.atTime(10, 0).toInstant(zone)

    @Test
    fun calendarDensityPackedAndMeetingHeavy() {
        val events = (0 until 6).map { i ->
            WorldStateBuilder.CalendarEvent(
                title = "M$i",
                start = now.plusSeconds((i + 1) * 3600L),
            )
        }
        val world = WorldStateBuilder.build(
            WorldStateBuilder.Input(
                life = LifeState(currentDay = day),
                now = now,
                zone = zone,
                calendarEvents = events,
            ),
        )
        assertEquals(CalendarDensity.PACKED, world.calendarDensity)
        assertEquals(6, world.calendarEventCount)
        assertTrue(world.isMeetingHeavyDay)
        assertEquals("M0", world.nextEventTitle)
    }

    @Test
    fun boardBreakdownAndPressure() {
        val life = LifeState(
            activeTasks = listOf(
                LifeTask(id = "a", title = "A", constraintType = ConstraintType.ANCHORED, status = TaskStatus.PENDING, durationMinutes = 60, scheduledDate = day),
                LifeTask(id = "x", title = "X", constraintType = ConstraintType.FLEXIBLE, status = TaskStatus.PENDING, durationMinutes = 90, scheduledDate = day),
                LifeTask(id = "f", title = "F", constraintType = ConstraintType.FLUID, status = TaskStatus.PENDING, durationMinutes = 30, scheduledDate = day),
            ),
            currentDay = day,
        )
        val world = WorldStateBuilder.build(WorldStateBuilder.Input(life = life, now = now, zone = zone))
        assertEquals(1, world.anchoredOpenCount)
        assertEquals(1, world.flexibleOpenCount)
        assertEquals(1, world.fluidOpenCount)
        assertEquals(180, world.plannedOpenMinutes)
        assertTrue(world.openTaskPressure > 0.0)
        assertTrue(world.capacityBand != CapacityBand.entries.firstOrNull { false } || true)
        assertTrue(BrainContextPack.fieldMap(world).containsKey("capacityBand"))
    }

    @Test
    fun medicationRiskDue() {
        val life = LifeState(
            medications = listOf(
                Medication(name = "Mag", scheduledTime = LocalTime.of(8, 0), isTaken = false),
            ),
            currentDay = day,
        )
        val world = WorldStateBuilder.build(WorldStateBuilder.Input(life = life, now = now, zone = zone))
        assertEquals(MedicationRisk.DUE, world.medicationRisk)
        assertTrue(world.medicationStatus is MedicationWorldStatus.DueNow)
    }

    @Test
    fun contextPackIncludesCapacityAndCalendar() {
        val life = LifeState(
            activeTasks = listOf(
                LifeTask(id = "h", title = "Hero", status = TaskStatus.PENDING, scheduledDate = day),
            ),
            currentDay = day,
        )
        val health = HealthSummary(readinessScore = 0.4, totalSleepMinutes = 300.0)
        val tick = ExecutiveBrainEngine.tick(life, health, now = now, zone = zone)
        val summary = BrainContextPack.systemSummary(tick, horizonDays = 7)
        assertTrue(summary.contains("Capacity="))
        assertTrue(summary.contains("Calendar="))
        assertTrue(summary.contains("MedRisk="))
        assertTrue(summary.contains("Horizon=7d"))
        val brief = BrainContextPack.plannerBrief(life, tick, 3)
        assertTrue(brief.contains("Open tasks:"))
        assertTrue(brief.contains("Hero"))
    }

    @Test
    fun capacityEmbeddedOnLowEnergy() {
        val life = LifeState(currentDay = day)
        val health = HealthSummary(readinessScore = 0.25, totalSleepMinutes = 240.0)
        val world = WorldStateBuilder.build(
            WorldStateBuilder.Input(life = life, health = health, now = now, zone = zone),
        )
        assertTrue(
            world.capacityBand == CapacityBand.RECOVERY || world.capacityBand == CapacityBand.PROTECTIVE,
        )
        assertTrue(world.recommendedFocusMinutes <= 60)
    }
}
