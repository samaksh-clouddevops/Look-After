package com.lookafter.core.calendar

import com.lookafter.core.brain.WorldStateBuilder
import com.lookafter.core.serialization.InstantSerializer
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.serialization.Serializable

@Serializable
data class CalendarEvent(
    val id: String,
    val title: String,
    @Serializable(with = InstantSerializer::class)
    val start: Instant,
    @Serializable(with = InstantSerializer::class)
    val end: Instant? = null,
    val isAllDay: Boolean = false,
) {
    fun toWorldCalendarEvent(): WorldStateBuilder.CalendarEvent =
        WorldStateBuilder.CalendarEvent(title = title, start = start, end = end)
}

/** Port-friendly provider contract (Android CalendarContract / iOS EventKit). */
interface CalendarEventsProvider {
    suspend fun eventsForDay(day: LocalDate, zone: ZoneId = ZoneId.systemDefault()): List<CalendarEvent>
}

/** Deterministic stub for tests and demo devices without calendar permission. */
class StubCalendarEventsProvider(
    private val seed: List<CalendarEvent> = emptyList(),
) : CalendarEventsProvider {
    override suspend fun eventsForDay(day: LocalDate, zone: ZoneId): List<CalendarEvent> {
        val start = day.atStartOfDay(zone).toInstant()
        val end = day.plusDays(1).atStartOfDay(zone).toInstant()
        return seed.filter { it.start >= start && it.start < end }
            .sortedBy { it.start }
    }
}
