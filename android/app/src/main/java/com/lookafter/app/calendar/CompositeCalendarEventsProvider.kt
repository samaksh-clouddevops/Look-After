package com.lookafter.app.calendar

import com.lookafter.core.calendar.CalendarEvent
import com.lookafter.core.calendar.CalendarEventsProvider
import java.time.LocalDate
import java.time.ZoneId

/**
 * Prefer device calendar when permitted/non-empty; otherwise fall back to stub/demo.
 */
class CompositeCalendarEventsProvider(
    private val device: DeviceCalendarEventsProvider,
    private val fallback: CalendarEventsProvider,
) : CalendarEventsProvider {

    override suspend fun eventsForDay(day: LocalDate, zone: ZoneId): List<CalendarEvent> {
        if (device.hasPermission()) {
            val real = device.eventsForDay(day, zone)
            if (real.isNotEmpty()) return real
        }
        return fallback.eventsForDay(day, zone)
    }
}
