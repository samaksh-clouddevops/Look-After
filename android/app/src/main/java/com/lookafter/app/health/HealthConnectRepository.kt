package com.lookafter.app.health

import android.content.Context
import com.lookafter.core.health.HealthSummary
import java.time.Instant
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Platform facade for Health Connect with automatic demo fallback.
 *
 * - When SDK is available + permissions granted → real aggregates
 * - Otherwise (or when demo is preferred) → deterministic demo metrics
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
        return next
    }
}
