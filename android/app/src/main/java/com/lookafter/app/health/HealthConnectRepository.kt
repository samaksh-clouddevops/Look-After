package com.lookafter.app.health

import com.lookafter.core.health.HealthSummary
import java.time.Instant
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Platform adapter for Android Health Connect.
 *
 * Phase-1: in-memory stub with deterministic demo data so UI / briefing can
 * render readiness without requiring the Health Connect APK on every device.
 * Replace [refresh] with Health Connect client reads when integrating the SDK.
 */
class HealthConnectRepository {

    private val _summary = MutableStateFlow(HealthSummary.EMPTY)
    val summary: StateFlow<HealthSummary> = _summary.asStateFlow()

    private val _permissionGranted = MutableStateFlow(false)
    val permissionGranted: StateFlow<Boolean> = _permissionGranted.asStateFlow()

    fun markPermission(granted: Boolean) {
        _permissionGranted.value = granted
    }

    /**
     * Pull latest metrics. Stub seeds a calm "good sleep" sample when
     * permission is granted so Briefing/Health screens are demonstrable.
     */
    suspend fun refresh(now: Instant = Instant.now()): HealthSummary {
        val next = if (_permissionGranted.value) {
            HealthSummary(
                totalSleepMinutes = 420.0,
                sleepQualityScore = 0.78,
                restingHeartRate = 58.0,
                hrvSdnn = 42.0,
                steps = 3200,
                activeEnergyKcal = 180.0,
                readinessScore = 0.72,
                capturedAt = now,
            )
        } else {
            HealthSummary.EMPTY
        }
        _summary.value = next
        return next
    }
}
