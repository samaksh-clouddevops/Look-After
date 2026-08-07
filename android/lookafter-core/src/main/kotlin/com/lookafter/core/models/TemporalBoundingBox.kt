package com.lookafter.core.models

import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import kotlinx.serialization.Serializable

/**
 * Same-day fence so Lunch cannot slide into Dinner.
 * Hours are local clock hours in [0, 23].
 * Mirrors iOS `TemporalBoundingBox`.
 */
@Serializable
data class TemporalBoundingBox(
    val earliestStartHour: Int,
    val latestStartHour: Int,
) {
    init {
        require(earliestStartHour in 0..23) { "earliestStartHour must be 0..23" }
        require(latestStartHour in 0..23) { "latestStartHour must be 0..23" }
        require(latestStartHour >= earliestStartHour) {
            "latestStartHour must be >= earliestStartHour"
        }
    }

    fun contains(start: Instant, zone: ZoneId = ZoneOffset.UTC): Boolean {
        val local = LocalDateTime.ofInstant(start, zone)
        val fractional = local.hour + local.minute / 60.0
        return fractional >= earliestStartHour.toDouble() &&
            fractional <= latestStartHour.toDouble() + 0.99
    }

    /**
     * Clamp [start] into the box on [day].
     * Returns null when start is past the latest allowable start.
     */
    fun clampStart(
        start: Instant,
        day: LocalDate,
        zone: ZoneId = ZoneOffset.UTC,
    ): Instant? {
        val earliest = day.atTime(earliestStartHour, 0).atZone(zone).toInstant()
        val latest = day.atTime(latestStartHour, 59).atZone(zone).toInstant()
        return when {
            start < earliest -> earliest
            start > latest -> null
            else -> start
        }
    }
}
