package com.lookafter.core.health

import com.lookafter.core.serialization.InstantSerializer
import java.time.Instant
import kotlinx.serialization.Serializable

/**
 * Cross-platform health snapshot — mirrors iOS `HealthSummary` fields
 * used by Briefing / Brain. Platform adapters (Health Connect / HealthKit)
 * populate this; core stays free of Android APIs.
 */
@Serializable
data class HealthSummary(
    val totalSleepMinutes: Double? = null,
    val sleepQualityScore: Double? = null,
    val restingHeartRate: Double? = null,
    val hrvSdnn: Double? = null,
    val steps: Int? = null,
    val activeEnergyKcal: Double? = null,
    val readinessScore: Double? = null,
    @Serializable(with = InstantSerializer::class)
    val capturedAt: Instant = Instant.EPOCH,
) {
    val sleepHours: Double?
        get() = totalSleepMinutes?.div(60.0)

    val readinessLabel: String
        get() {
            val score = readinessScore ?: return "Unknown"
            return when {
                score >= 0.8 -> "Peak"
                score >= 0.6 -> "Good"
                score >= 0.4 -> "Moderate"
                score >= 0.2 -> "Low"
                else -> "Recover"
            }
        }

    companion object {
        val EMPTY = HealthSummary()
    }
}
