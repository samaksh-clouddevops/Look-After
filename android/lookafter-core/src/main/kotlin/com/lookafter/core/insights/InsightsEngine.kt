package com.lookafter.core.insights

import com.lookafter.core.engine.LifeState
import com.lookafter.core.health.HealthHistorySeries
import com.lookafter.core.health.HealthSummary
import com.lookafter.core.health.RollingHealthAverages
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.Priority
import com.lookafter.core.models.TaskStatus
import com.lookafter.core.serialization.LocalDateSerializer
import java.time.LocalDate
import java.time.ZoneId
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
data class TagHeat(
    val tag: String,
    val count: Int = 0,
    val heat: Double = 0.0,
)

@Serializable
data class InsightsSnapshot(
    @Serializable(with = LocalDateSerializer::class)
    val asOf: LocalDate,
    val windowDays: Int = 7,
    val completionRate7d: Double = 0.0,
    val focusMinutes7d: Int = 0,
    val completed7d: Int = 0,
    val openNow: Int = 0,
    val parkedNow: Int = 0,
    val somedayNow: Int = 0,
    val streakDays: Int = 0,
    val streakQuality: Double = 0.0,
    val anchoredShare: Double = 0.0,
    val flexibleShare: Double = 0.0,
    val fluidShare: Double = 0.0,
    val highPriorityOpen: Int = 0,
    val medAdherenceToday: Double = 0.0,
    val readiness: Double? = null,
    val avgSleepHours7d: Double? = null,
    val avgReadiness7d: Double? = null,
    val sleepTrend: String = "flat",
    val readinessTrend: String = "flat",
    val topTags: List<String> = emptyList(),
    val tagHeat: List<TagHeat> = emptyList(),
    val dayBars: List<DayInsight> = emptyList(),
    val weeklyFocusHours: Double = 0.0,
    val performanceScore: Double = 0.0,
    val performanceLabel: String = "Steady",
    val headline: String = "",
    val coachingLine: String = "",
    val reviewHints: List<String> = emptyList(),
) {
    companion object {
        val EMPTY = InsightsSnapshot(asOf = LocalDate.EPOCH)
    }
}

/** Pure analytics for Insights / Performance (Phase D2). */
object InsightsEngine {

    fun compute(
        state: LifeState,
        health: HealthSummary = HealthSummary.EMPTY,
        asOf: LocalDate = state.currentDay ?: LocalDate.now(),
        windowDays: Int = 7,
        healthHistory: HealthHistorySeries = HealthHistorySeries.EMPTY,
        rollingHealth: RollingHealthAverages = RollingHealthAverages(),
        zone: ZoneId = ZoneId.systemDefault(),
    ): InsightsSnapshot {
        val start = asOf.minusDays((windowDays - 1).toLong())
        val active = state.activeTasks
        val completed = active.filter { it.status == TaskStatus.COMPLETED }
        val open = active.filter { it.status.isActive }

        val completedInWindow = completed.filter { t ->
            val d = t.completedAt?.atZone(zone)?.toLocalDate() ?: t.scheduledDate
            d != null && !d.isBefore(start) && !d.isAfter(asOf)
        }
        val focusMinutes = completedInWindow.sumOf { it.durationMinutes.coerceAtLeast(0) }
        val createdProxy = (completedInWindow.size + open.size).coerceAtLeast(1)
        val rate = completedInWindow.size.toDouble() / createdProxy.toDouble()

        val dayBars = (0 until windowDays).map { offset ->
            val day = start.plusDays(offset.toLong())
            val dayDone = completedInWindow.filter {
                val d = it.completedAt?.atZone(zone)?.toLocalDate() ?: it.scheduledDate
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
        val streakDaysList = dayBars.takeLast(streak).filter { it.completed > 0 }
        val streakQuality =
            if (streakDaysList.isEmpty()) 0.0 else streakDaysList.map { it.completed }.average()

        val anchored = open.count { it.constraintType == ConstraintType.ANCHORED }
        val flexible = open.count { it.constraintType == ConstraintType.FLEXIBLE }
        val fluid = open.count { it.constraintType == ConstraintType.FLUID }
        val openN = open.size.coerceAtLeast(1).toDouble()

        val tagCounts = active.flatMap { it.tags }
            .filter { it.isNotBlank() && it !in setOf("capture", "plan", "manual") }
            .groupingBy { it }
            .eachCount()
        val tagTotal = tagCounts.values.sum().coerceAtLeast(1).toDouble()
        val tagHeat = tagCounts.entries.sortedByDescending { it.value }.take(8)
            .map { TagHeat(it.key, it.value, it.value / tagTotal) }

        val avgSleep = rollingHealth.sleepHours ?: healthHistory.averageSleepHours()
        val avgReady = rollingHealth.readinessScore
            ?: healthHistory.averageReadiness()
            ?: health.readinessScore

        val perf = performanceScore(rate, streak, focusMinutes, avgReady, state.medicationAdherenceRate)

        return InsightsSnapshot(
            asOf = asOf,
            windowDays = windowDays,
            completionRate7d = rate.coerceIn(0.0, 1.0),
            focusMinutes7d = focusMinutes,
            completed7d = completedInWindow.size,
            openNow = open.size,
            parkedNow = state.parkedQueue.size,
            somedayNow = state.somedayVault.size,
            streakDays = streak,
            streakQuality = streakQuality,
            anchoredShare = anchored / openN,
            flexibleShare = flexible / openN,
            fluidShare = fluid / openN,
            highPriorityOpen = open.count {
                it.priority == Priority.HIGH || it.priority == Priority.CRITICAL
            },
            medAdherenceToday = state.medicationAdherenceRate,
            readiness = health.readinessScore,
            avgSleepHours7d = avgSleep,
            avgReadiness7d = avgReady,
            sleepTrend = rollingHealth.sleepTrendLabel,
            readinessTrend = rollingHealth.readinessTrendLabel,
            topTags = tagHeat.map { it.tag },
            tagHeat = tagHeat,
            dayBars = dayBars,
            weeklyFocusHours = focusMinutes / 60.0,
            performanceScore = perf,
            performanceLabel = performanceLabel(perf),
            headline = when {
                streak >= 3 -> "$streak-day completion streak"
                focusMinutes >= 120 -> "${focusMinutes / 60}h+ deep work this week"
                open.isEmpty() -> "Board is clear"
                else -> "${open.size} open · ${completedInWindow.size} done (${windowDays}d)"
            },
            coachingLine = coachingLine(rate, open.size, anchored / openN, avgReady, state),
            reviewHints = reviewHints(state, dayBars, tagHeat, rate, fluid),
        )
    }

    private fun performanceScore(
        rate: Double, streak: Int, focusMinutes: Int, readiness: Double?, med: Double,
    ): Double {
        val r = rate.coerceIn(0.0, 1.0) * 0.35
        val s = (streak / 7.0).coerceIn(0.0, 1.0) * 0.2
        val f = (focusMinutes / 300.0).coerceIn(0.0, 1.0) * 0.25
        val h = (readiness ?: 0.55).coerceIn(0.0, 1.0) * 0.15
        val m = if (med <= 0.0) 0.05 else med.coerceIn(0.0, 1.0) * 0.05
        return (r + s + f + h + m).coerceIn(0.0, 1.0)
    }

    private fun performanceLabel(score: Double): String = when {
        score >= 0.8 -> "Strong"
        score >= 0.6 -> "Solid"
        score >= 0.4 -> "Steady"
        score >= 0.25 -> "Soft"
        else -> "Recover"
    }

    private fun coachingLine(
        rate: Double, open: Int, anchoredShare: Double, readiness: Double?, state: LifeState,
    ): String = when {
        rate < 0.3 && open > 5 -> "Completion is thin — strip fluid work and protect one hero."
        anchoredShare > 0.6 -> "Day is meeting-heavy. Guard recovery gaps."
        (readiness ?: 1.0) < 0.45 -> "Readiness is low — shorten blocks, bias recovery."
        state.medicationAdherenceRate in 0.01..0.99 -> "Meds mid-stream — finish the remaining doses."
        open > 12 -> "Board is noisy — park or someday the bottom half."
        else -> "Keep the cadence. Small wins compound."
    }

    private fun reviewHints(
        state: LifeState, bars: List<DayInsight>, tags: List<TagHeat>, rate: Double, fluidOpen: Int,
    ): List<String> {
        val hints = mutableListOf<String>()
        if (fluidOpen >= 4) hints += "Park or schedule $fluidOpen fluid items"
        if (state.parkedQueue.size >= 5) hints += "Unpark one parked item this week"
        if (rate < 0.4) hints += "Aim for one intentional completion daily"
        val quiet = bars.count { it.completed == 0 }
        if (quiet >= 3) hints += "$quiet quiet days — protect a minimum viable block"
        tags.firstOrNull()?.let { hints += "Hottest tag: #${it.tag} (${it.count})" }
        if (hints.isEmpty()) hints += "Weekly review: celebrate streaks, then cut noise"
        return hints.take(5)
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
