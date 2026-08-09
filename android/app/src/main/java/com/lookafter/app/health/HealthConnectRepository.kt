package com.lookafter.app.health

import android.content.Context
import com.lookafter.core.health.HealthHistoryEngine
import com.lookafter.core.health.HealthHistorySeries
import com.lookafter.core.health.HealthSummary
import com.lookafter.core.health.RollingHealthAverages
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Platform facade for Health Connect with automatic demo fallback.
 *
 * - When SDK is available + permissions granted → real aggregates
 * - Otherwise (or when demo is preferred) → deterministic demo metrics
 * - Multi-day [history] powers Health charts (Phase D1)
 */
class HealthConnectRepository(
    private val realSource: HealthDataSource,
    private val demoSource: HealthDataSource = DemoHealthDataSource(),
) {
    constructor(context: Context) : this(
        realSource = HealthConnectDataSource(context.applicationContext),
        demoSource = DemoHealthDataSource(),
    )

    /** Test / demo convenience constructor (demo-only). */
    constructor() : this(
        realSource = DemoHealthDataSource(),
        demoSource = DemoHealthDataSource(),
    )

    private val _summary = MutableStateFlow(HealthSummary.EMPTY)
    val summary: StateFlow<HealthSummary> = _summary.asStateFlow()

    private val _history = MutableStateFlow(HealthHistorySeries.EMPTY)
    val history: StateFlow<HealthHistorySeries> = _history.asStateFlow()

    private val _rolling = MutableStateFlow(RollingHealthAverages())
    val rollingAverages: StateFlow<RollingHealthAverages> = _rolling.asStateFlow()

    private val _permissionGranted = MutableStateFlow(false)
    val permissionGranted: StateFlow<Boolean> = _permissionGranted.asStateFlow()

    private val _availability = MutableStateFlow(HealthConnectAvailability.UNKNOWN)
    val availability: StateFlow<HealthConnectAvailability> = _availability.asStateFlow()

    private val _usingDemo = MutableStateFlow(true)
    val usingDemo: StateFlow<Boolean> = _usingDemo.asStateFlow()

    var preferDemoFallback: Boolean = false

    fun requiredPermissions(): Set<String> = realSource.requiredPermissions()

    fun markPermission(granted: Boolean) {
        _permissionGranted.value = granted
    }

    suspend fun refreshAvailability() {
        _availability.value = realSource.availability()
        val granted = runCatching { realSource.hasAllPermissions() }.getOrDefault(false)
        if (granted) _permissionGranted.value = true
    }

    suspend fun refresh(now: Instant = Instant.now()): HealthSummary {
        refreshAvailability()
        val canReal = _availability.value == HealthConnectAvailability.AVAILABLE &&
            _permissionGranted.value &&
            !preferDemoFallback
        val next = if (canReal) {
            val real = realSource.readSummary(now)
            if (real.readinessScore != null || real.steps != null || real.totalSleepMinutes != null) {
                _usingDemo.value = false
                real
            } else {
                _usingDemo.value = true
                if (_permissionGranted.value) demoSource.readSummary(now) else HealthSummary.EMPTY
            }
        } else if (_permissionGranted.value || preferDemoFallback) {
            _usingDemo.value = true
            demoSource.readSummary(now)
        } else {
            _usingDemo.value = false
            HealthSummary.EMPTY
        }
        _summary.value = next
        // Keep history in sync with the same source decision.
        refreshHistory(endInclusive = now.atZone(ZoneId.systemDefault()).toLocalDate())
        return next
    }

    suspend fun refreshHistory(
        endInclusive: LocalDate = LocalDate.now(),
        dayCount: Int = 7,
        zone: ZoneId = ZoneId.systemDefault(),
    ): HealthHistorySeries {
        refreshAvailability()
        val canReal = _availability.value == HealthConnectAvailability.AVAILABLE &&
            _permissionGranted.value &&
            !preferDemoFallback
        val series = if (canReal) {
            val real = realSource.readHistory(endInclusive, dayCount, zone)
            if (real.days.isNotEmpty()) {
                _usingDemo.value = false
                real
            } else if (_permissionGranted.value || preferDemoFallback) {
                _usingDemo.value = true
                demoSource.readHistory(endInclusive, dayCount, zone)
            } else {
                HealthHistorySeries.EMPTY
            }
        } else if (_permissionGranted.value || preferDemoFallback) {
            _usingDemo.value = true
            demoSource.readHistory(endInclusive, dayCount, zone)
        } else {
            // Always show demo series on the Health screen when empty so charts aren't blank.
            _usingDemo.value = true
            HealthHistoryEngine.demoSeries(endInclusive, dayCount)
        }
        _history.value = series
        _rolling.value = HealthHistoryEngine.rollingAverages(series)
        return series
    }
}
