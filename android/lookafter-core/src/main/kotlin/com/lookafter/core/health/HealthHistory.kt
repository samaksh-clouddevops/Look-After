package com.lookafter.core.health

import com.lookafter.core.serialization.LocalDateSerializer
import java.time.LocalDate
import kotlin.math.roundToInt
import kotlinx.serialization.Serializable

/** One calendar day's health metrics for charts / rolling averages. */
@Serializable
data class HealthDayPoint(
    @Serializable(with = LocalDateSerializer::class)
    val day: LocalDate,
    val sleepHours: Double? = null,
    val readinessScore: Double? = null,
    val steps: Int? = null,
    val restingHeartRate: Double? = null,
    val activeEnergyKcal: Double? = null,
) {
    val sleepMinutes: Double? get() = sleepHours?.times(60.0)
}

/**
 * Multi-day series used by Health charts and capacity rolling averages.
 * Ordered oldest → newest; length typically 7 or 14.
 */
@Serializable
data class HealthHistorySeries(
    val days: List<HealthDayPoint> = emptyList(),
    val sourceLabel: String = "demo",
) {
    val size: Int get() = days.size

    fun averageSleepHours(): Double? =
        days.mapNotNull { it.sleepHours }.takeIf { it.isNotEmpty() }?.average()

    fun averageReadiness(): Double? =
        days.mapNotNull { it.readinessScore }.takeIf { it.isNotEmpty() }?.average()

    fun averageSteps(): Double? =
        days.mapNotNull { it.steps?.toDouble() }.takeIf { it.isNotEmpty() }?.average()

    fun last(): HealthDayPoint? = days.lastOrNull()

    fun toSummary(): HealthSummary {
        val last = last() ?: return HealthSummary.EMPTY
        return HealthSummary(
            totalSleepMinutes = last.sleepMinutes,
            sleepQualityScore = last.readinessScore, // approximate when quality unknown
            restingHeartRate = last.restingHeartRate,
            steps = last.steps,
            activeEnergyKcal = last.activeEnergyKcal,
            readinessScore = last.readinessScore,
        )
    }

    companion object {
        val EMPTY = HealthHistorySeries()
    }
}

/** Pure aggregation / demo-generation helpers (no Android). */
object HealthHistoryEngine {

    fun rollingAverages(series: HealthHistorySeries): RollingHealthAverages {
        val sleep = series.averageSleepHours()
        val readiness = series.averageReadiness()
        val steps = series.averageSteps()
        return RollingHealthAverages(
            sleepHours = sleep,
            readinessScore = readiness,
            steps = steps?.roundToInt(),
            sleepTrendLabel = trendLabel(series.days.mapNotNull { it.sleepHours }),
            readinessTrendLabel = trendLabel(series.days.mapNotNull { it.readinessScore }),
        )
    }

    /**
     * Deterministic 7-day demo series ending on [endInclusive].
     * Values vary mildly by day-of-year for visual interest.
     */
    fun demoSeries(
        endInclusive: LocalDate = LocalDate.now(),
        dayCount: Int = 7,
    ): HealthHistorySeries {
        val n = dayCount.coerceIn(3, 30)
        val start = endInclusive.minusDays((n - 1).toLong())
        val points = (0 until n).map { i ->
            val day = start.plusDays(i.toLong())
            val seed = day.dayOfYear + day.year
            val sleep = 5.5 + ((seed * 17) % 25) / 10.0 // 5.5–8.0
            val readiness = (0.35 + ((seed * 13) % 55) / 100.0).coerceIn(0.2, 0.95)
            val steps = 3500 + (seed * 97) % 9000
            val rhr = 52.0 + ((seed * 3) % 18)
            HealthDayPoint(
                day = day,
                sleepHours = (sleep * 10).roundToInt() / 10.0,
                readinessScore = (readiness * 100).roundToInt() / 100.0,
                steps = steps,
                restingHeartRate = rhr,
                activeEnergyKcal = 200.0 + (seed % 400),
            )
        }
        return HealthHistorySeries(days = points, sourceLabel = "demo")
    }

    fun fromDailySummaries(
        points: List<HealthDayPoint>,
        sourceLabel: String,
    ): HealthHistorySeries =
        HealthHistorySeries(
            days = points.sortedBy { it.day },
            sourceLabel = sourceLabel,
        )

    /** Simple end-vs-start trend. */
    private fun trendLabel(values: List<Double>): String {
        if (values.size < 2) return "flat"
        val first = values.take(values.size / 2).average()
        val last = values.takeLast((values.size + 1) / 2).average()
        val delta = last - first
        val thr = (values.maxOrNull() ?: 1.0) * 0.05
        return when {
            delta > thr -> "up"
            delta < -thr -> "down"
            else -> "flat"
        }
    }
}

@Serializable
data class RollingHealthAverages(
    val sleepHours: Double? = null,
    val readinessScore: Double? = null,
    val steps: Int? = null,
    val sleepTrendLabel: String = "flat",
    val readinessTrendLabel: String = "flat",
)
