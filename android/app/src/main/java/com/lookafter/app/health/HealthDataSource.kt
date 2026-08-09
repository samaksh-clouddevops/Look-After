package com.lookafter.app.health

import android.content.Context
import com.lookafter.core.health.HealthDayPoint
import com.lookafter.core.health.HealthHistoryEngine
import com.lookafter.core.health.HealthHistorySeries
import com.lookafter.core.health.HealthSummary
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/** Capability / availability of the Health Connect backend. */
enum class HealthConnectAvailability {
    AVAILABLE,
    NOT_INSTALLED,
    UNSUPPORTED,
    UNKNOWN,
}

/**
 * Abstraction so tests can inject stubs and production can use the SDK client.
 */
interface HealthDataSource {
    suspend fun availability(): HealthConnectAvailability
    suspend fun hasAllPermissions(): Boolean
    fun requiredPermissions(): Set<String>
    suspend fun readSummary(now: Instant = Instant.now()): HealthSummary
    suspend fun readHistory(
        endInclusive: LocalDate = LocalDate.now(),
        dayCount: Int = 7,
        zone: ZoneId = ZoneId.systemDefault(),
    ): HealthHistorySeries = HealthHistorySeries.EMPTY
}

/**
 * Demo data used when HC is missing / denied so UI remains demonstrable.
 */
class DemoHealthDataSource : HealthDataSource {
    override suspend fun availability(): HealthConnectAvailability =
        HealthConnectAvailability.NOT_INSTALLED

    override suspend fun hasAllPermissions(): Boolean = false

    override fun requiredPermissions(): Set<String> = emptySet()

    override suspend fun readSummary(now: Instant): HealthSummary {
        val day = now.atZone(ZoneId.systemDefault()).toLocalDate()
        val series = HealthHistoryEngine.demoSeries(endInclusive = day, dayCount = 7)
        val last = series.last() ?: return HealthSummary(capturedAt = now)
        return HealthSummary(
            totalSleepMinutes = last.sleepMinutes,
            sleepQualityScore = last.readinessScore,
            restingHeartRate = last.restingHeartRate,
            hrvSdnn = 42.0,
            steps = last.steps,
            activeEnergyKcal = last.activeEnergyKcal,
            readinessScore = last.readinessScore,
            capturedAt = now,
        )
    }

    override suspend fun readHistory(
        endInclusive: LocalDate,
        dayCount: Int,
        zone: ZoneId,
    ): HealthHistorySeries = HealthHistoryEngine.demoSeries(endInclusive, dayCount)
}

/**
 * Real Health Connect reader. Uses reflection-friendly SDK APIs when the
 * library is on the classpath; catches missing provider errors and returns empty.
 */
class HealthConnectDataSource(
    private val context: Context,
) : HealthDataSource {

    private val client by lazy {
        runCatching {
            androidx.health.connect.client.HealthConnectClient.getOrCreate(context)
        }.getOrNull()
    }

    override suspend fun availability(): HealthConnectAvailability {
        val status = runCatching {
            androidx.health.connect.client.HealthConnectClient.getSdkStatus(context)
        }.getOrNull() ?: return HealthConnectAvailability.UNKNOWN
        return when (status) {
            androidx.health.connect.client.HealthConnectClient.SDK_AVAILABLE ->
                HealthConnectAvailability.AVAILABLE
            androidx.health.connect.client.HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED ->
                HealthConnectAvailability.NOT_INSTALLED
            else -> HealthConnectAvailability.UNSUPPORTED
        }
    }

    override fun requiredPermissions(): Set<String> = setOf(
        androidx.health.connect.client.permission.HealthPermission.getReadPermission(
            androidx.health.connect.client.records.StepsRecord::class,
        ),
        androidx.health.connect.client.permission.HealthPermission.getReadPermission(
            androidx.health.connect.client.records.SleepSessionRecord::class,
        ),
        androidx.health.connect.client.permission.HealthPermission.getReadPermission(
            androidx.health.connect.client.records.HeartRateRecord::class,
        ),
        androidx.health.connect.client.permission.HealthPermission.getReadPermission(
            androidx.health.connect.client.records.RestingHeartRateRecord::class,
        ),
        androidx.health.connect.client.permission.HealthPermission.getReadPermission(
            androidx.health.connect.client.records.HeartRateVariabilityRmssdRecord::class,
        ),
        androidx.health.connect.client.permission.HealthPermission.getReadPermission(
            androidx.health.connect.client.records.ActiveCaloriesBurnedRecord::class,
        ),
    )

    override suspend fun hasAllPermissions(): Boolean {
        val c = client ?: return false
        val granted = runCatching {
            c.permissionController.getGrantedPermissions()
        }.getOrDefault(emptySet())
        return granted.containsAll(requiredPermissions())
    }

    override suspend fun readSummary(now: Instant): HealthSummary {
        val c = client ?: return HealthSummary.EMPTY
        if (!hasAllPermissions()) return HealthSummary.EMPTY
        val start = now.minus(1, ChronoUnit.DAYS)
        val steps = readSteps(c, start, now)
        val sleepMin = readSleepMinutes(c, start, now)
        val rhr = readRestingHr(c, start, now)
        val hrv = readHrv(c, start, now)
        val kcal = readActiveKcal(c, start, now)
        val readiness = estimateReadiness(sleepMin, rhr, hrv)
        return HealthSummary(
            totalSleepMinutes = sleepMin,
            sleepQualityScore = sleepMin?.let { (it / 480.0).coerceIn(0.0, 1.0) },
            restingHeartRate = rhr,
            hrvSdnn = hrv,
            steps = steps,
            activeEnergyKcal = kcal,
            readinessScore = readiness,
            capturedAt = now,
        )
    }

    override suspend fun readHistory(
        endInclusive: LocalDate,
        dayCount: Int,
        zone: ZoneId,
    ): HealthHistorySeries {
        val c = client ?: return HealthHistorySeries.EMPTY
        if (!hasAllPermissions()) return HealthHistorySeries.EMPTY
        val n = dayCount.coerceIn(3, 30)
        val startDay = endInclusive.minusDays((n - 1).toLong())
        val points = (0 until n).map { i ->
            val day = startDay.plusDays(i.toLong())
            val dayStart = day.atStartOfDay(zone).toInstant()
            val dayEnd = day.plusDays(1).atStartOfDay(zone).toInstant()
            val sleepMin = readSleepMinutes(c, dayStart, dayEnd)
            val steps = readSteps(c, dayStart, dayEnd)
            val rhr = readRestingHr(c, dayStart, dayEnd)
            val hrv = readHrv(c, dayStart, dayEnd)
            val kcal = readActiveKcal(c, dayStart, dayEnd)
            val readiness = estimateReadiness(sleepMin, rhr, hrv)
            HealthDayPoint(
                day = day,
                sleepHours = sleepMin?.div(60.0)?.let { (it * 10).toInt() / 10.0 },
                readinessScore = readiness,
                steps = steps,
                restingHeartRate = rhr,
                activeEnergyKcal = kcal,
            )
        }
        // If every day is empty, treat as no data.
        val hasAny = points.any {
            it.sleepHours != null || it.steps != null || it.readinessScore != null
        }
        if (!hasAny) return HealthHistorySeries.EMPTY
        return HealthHistoryEngine.fromDailySummaries(points, sourceLabel = "health-connect")
    }

    private suspend fun readSteps(
        client: androidx.health.connect.client.HealthConnectClient,
        start: Instant,
        end: Instant,
    ): Int? = runCatching {
        val request = androidx.health.connect.client.request.ReadRecordsRequest(
            recordType = androidx.health.connect.client.records.StepsRecord::class,
            timeRangeFilter = androidx.health.connect.client.time.TimeRangeFilter.between(start, end),
        )
        client.readRecords(request).records.sumOf { it.count }.toInt()
    }.getOrNull()

    private suspend fun readSleepMinutes(
        client: androidx.health.connect.client.HealthConnectClient,
        start: Instant,
        end: Instant,
    ): Double? = runCatching {
        val request = androidx.health.connect.client.request.ReadRecordsRequest(
            recordType = androidx.health.connect.client.records.SleepSessionRecord::class,
            timeRangeFilter = androidx.health.connect.client.time.TimeRangeFilter.between(start, end),
        )
        val records = client.readRecords(request).records
        if (records.isEmpty()) null
        else records.sumOf {
            java.time.Duration.between(it.startTime, it.endTime).toMinutes().toDouble()
        }
    }.getOrNull()

    private suspend fun readRestingHr(
        client: androidx.health.connect.client.HealthConnectClient,
        start: Instant,
        end: Instant,
    ): Double? = runCatching {
        val request = androidx.health.connect.client.request.ReadRecordsRequest(
            recordType = androidx.health.connect.client.records.RestingHeartRateRecord::class,
            timeRangeFilter = androidx.health.connect.client.time.TimeRangeFilter.between(start, end),
        )
        client.readRecords(request).records.lastOrNull()?.beatsPerMinute?.toDouble()
    }.getOrNull()

    private suspend fun readHrv(
        client: androidx.health.connect.client.HealthConnectClient,
        start: Instant,
        end: Instant,
    ): Double? = runCatching {
        val request = androidx.health.connect.client.request.ReadRecordsRequest(
            recordType = androidx.health.connect.client.records.HeartRateVariabilityRmssdRecord::class,
            timeRangeFilter = androidx.health.connect.client.time.TimeRangeFilter.between(start, end),
        )
        client.readRecords(request).records.lastOrNull()?.heartRateVariabilityMillis
    }.getOrNull()

    private suspend fun readActiveKcal(
        client: androidx.health.connect.client.HealthConnectClient,
        start: Instant,
        end: Instant,
    ): Double? = runCatching {
        val request = androidx.health.connect.client.request.ReadRecordsRequest(
            recordType = androidx.health.connect.client.records.ActiveCaloriesBurnedRecord::class,
            timeRangeFilter = androidx.health.connect.client.time.TimeRangeFilter.between(start, end),
        )
        client.readRecords(request).records.sumOf { it.energy.inKilocalories }
    }.getOrNull()

    private fun estimateReadiness(sleepMin: Double?, rhr: Double?, hrv: Double?): Double {
        var score = 0.5
        sleepMin?.let {
            score = (score * 0.4) + ((it / 480.0).coerceIn(0.0, 1.0) * 0.6)
        }
        hrv?.let {
            // Simple RMSSD heuristic (ms) — higher is better up to ~80.
            score = (score + (it / 80.0).coerceIn(0.0, 1.0)) / 2.0
        }
        rhr?.let {
            val rhrScore = when {
                it <= 55 -> 1.0
                it <= 65 -> 0.8
                it <= 75 -> 0.6
                else -> 0.4
            }
            score = (score + rhrScore) / 2.0
        }
        return score.coerceIn(0.0, 1.0)
    }
}
