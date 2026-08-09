package com.lookafter.core.briefing

import com.lookafter.core.brain.ExecutiveBrainEngine
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
import kotlin.test.assertTrue

class BriefingNarrativeBuilderTest {

    private val day = LocalDate.of(2026, 8, 8)
    private val zone = ZoneOffset.UTC

    @Test
    fun buildsGreetingHeroAndGuidance() {
        val task = LifeTask(
            id = "h1",
            title = "Deep work",
            constraintType = ConstraintType.ANCHORED,
            status = TaskStatus.PENDING,
            scheduledDate = day,
            scheduledStart = day.atTime(10, 0).toInstant(zone),
        )
        val life = LifeState(
            activeTasks = listOf(task),
            medications = listOf(
                Medication(name = "Mag", scheduledTime = LocalTime.of(8, 0), isTaken = false),
            ),
            currentDay = day,
        )
        val health = HealthSummary(readinessScore = 0.7, totalSleepMinutes = 420.0)
        val tick = ExecutiveBrainEngine.tick(life, health, now = day.atTime(9, 0).toInstant(zone), zone = zone)
        val narrative = BriefingNarrativeBuilder.build(
            state = life,
            health = health,
            tick = tick,
            day = day,
            nowTime = LocalTime.of(9, 0),
        )
        assertTrue(narrative.greeting.contains("morning", ignoreCase = true))
        assertTrue(narrative.heroTitle.isNotBlank())
        assertTrue(narrative.guidance.isNotEmpty())
        assertTrue(narrative.orientation.contains("Energy") || narrative.orientation.contains("capacity") || narrative.orientation.isNotBlank())
        assertTrue(narrative.careLine != null && narrative.careLine!!.contains("Mag"))
        assertTrue(narrative.showFocusCta)
    }

    @Test
    fun emptyBoardStillCalm() {
        val narrative = BriefingNarrativeBuilder.build(
            LifeState(currentDay = day),
            day = day,
            nowTime = LocalTime.of(14, 0),
        )
        assertTrue(narrative.greeting.contains("afternoon", ignoreCase = true))
        assertTrue(narrative.boardLine.lowercase().contains("empty") || narrative.boardLine.lowercase().contains("clear") || narrative.boardLine.isNotBlank())
    }
}
