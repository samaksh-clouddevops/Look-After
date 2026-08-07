package com.lookafter.core.insights

import com.lookafter.core.engine.LifeState
import com.lookafter.core.health.HealthSummary
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.TaskStatus
import com.lookafter.core.serialization.LocalDateSerializer
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import kotlinx.serialization.Serializable

@Serializable
data class DayInsight(
    @Serializable(with = LocalDateSerializer::class)
    val day: LocalDate,
    val completed: Int = 0,
    val focusMinutes: Int = 0,
    val open: Int = 0,
)

@Serializable
data class InsightsSnapshot(
    @Serializable(with = LocalDateSerializer::class)
    val asOf: LocalDate,
    val completionRate7d: Double = 0.0,
    val focusMinutes7d: Int = 0,
    val completed7d: Int = 0,
    val openNow: Int = 0,
    val parkedNow: Int = 0,
    val streakDays: Int = 0,
    val anchoredShare: Double = 0.0,
    val medAdherenceToday: Double = 0.0,
    val readiness: Double? = null,
    val topTags: List<String> = emptyList(),
    val dayBars: List<DayInsight> = emptyList(),
    val headline: String = "",
    val coachingLine: String = "",
) {
    companion object {
        val EMPTY = InsightsSnapshot(asOf = LocalDate.EPOCH)
    }
}

/**
 * Pure analytics projection from [LifeState] (+ optional health).
 * Powers Insights UI / weekly review depth.
 */
object InsightsEngine {

    fun compute(
        state: LifeState,
        health: HealthSummary = HealthSummary.EMPTY,
        asOf: LocalDate = state.currentDay ?: LocalDate.now(),
        windowDays: Int = 7,
    ): InsightsSnapshot {
        val start = asOf.minusDays((windowDays - 1).toLong())
        val active = state.activeTasks
        val completed = active.filter { it.status == TaskStatus.COMPLETED }
        val open = active.filter { it.status.isActive }

        val completedInWindow = completed.filter { t ->
            val d = t.completedAt?.atZone(java.time.ZoneId.systemDefault())?.toLocalDate()
                ?: t.scheduledDate
            d != null && !d.isBefore(start) && !d.isAfter(asOf)
        }
        val focusMinutes = completedInWindow.sumOf { it.durationMinutes.coerceAtLeast(0) }
        val createdProxy = (completedInWindow.size + open.size).coerceAtLeast(1)
        val rate = completedInWindow.size.toDouble() / createdProxy.toDouble()

        val dayBars = (0 until windowDays).map { offset ->
            val day = start.plusDays(offset.toLong())
            val dayDone = completedInWindow.filter {
                val d = it.completedAt?.atZone(java.time.ZoneId.systemDefault())?.toLocalDate()
                    ?: it.scheduledDate
                d == day
            }
            DayInsight(
                day = day,
                completed = dayDone.size,
                focusMinutes = dayDone.sumOf { it.durationMinutes },
                open = open.count { it.scheduledDate == day },
            )
        }

        val streak = streakEnding(asOf, dayBars)
        val anchored = open.count { it.constraintType == ConstraintType.ANCHORED }
        val anchoredShare = if (open.isEmpty()) 0.0 else anchored.toDouble() / open.size

        val tags = active.flatMap { it.tags }
            .filter { it.isNotBlank() && it != "capture" && it != "plan" }
            .groupingBy { it }
            .eachCount()
            .entries
            .sortedByDescending { it.value }
            .take(5)
            .map { it.key }

        val headline = when {
            streak >= 3 -> "$streak-day completion streak"
            focusMinutes >= 120 -> "${focusMinutes / 60}h+ deep work this week"
            open.isEmpty() -> "Board is clear"
            else -> "${open.size} open · ${completedInWindow.size} done (7d)"
        }

        val coaching = when {
            rate < 0.3 && open.size > 5 -> "Completion is thin — strip fluid work and protect one hero."
            anchoredShare > 0.6 -> "Day is meeting-heavy. Guard recovery gaps."
            (health.readinessScore ?: 1.0) < 0.45 -> "Readiness is low — shorten blocks, bias recovery."
            state.medicationAdherenceRate in 0.01..0.99 -> "Meds mid-stream — finish the remaining doses."
            else -> "Keep the cadence. Small wins compound."
        }

        return InsightsSnapshot(
            asOf = asOf,
            completionRate7d = rate.coerceIn(0.0, 1.0),
            focusMinutes7d = focusMinutes,
            completed7d = completedInWindow.size,
            openNow = open.size,
            parkedNow = state.parkedQueue.size,
            streakDays = streak,
            anchoredShare = anchoredShare,
            medAdherenceToday = state.medicationAdherenceRate,
            readiness = health.readinessScore,
            topTags = tags,
            dayBars = dayBars,
            headline = headline,
            coachingLine = coaching,
        )
    }

    private fun streakEnding(asOf: LocalDate, bars: List<DayInsight>): Int {
        var streak = 0
        for (i in bars.indices.reversed()) {
            val b = bars[i]
            if (b.day.isAfter(asOf)) continue
            if (b.completed > 0) streak++ else break
        }
        return streak
    }
}
