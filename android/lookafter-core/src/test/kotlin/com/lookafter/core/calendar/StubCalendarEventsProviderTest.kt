package com.lookafter.core.calendar

import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlinx.coroutines.test.runTest

class StubCalendarEventsProviderTest {

    @Test
    fun filtersByDay() = runTest {
        val zone = ZoneOffset.UTC
        val day = LocalDate.of(2026, 8, 7)
        val other = day.plusDays(1)
        val seed = listOf(
            CalendarEvent(
                id = "1",
                title = "A",
                start = day.atTime(LocalTime.of(9, 0)).toInstant(zone),
            ),
            CalendarEvent(
                id = "2",
                title = "B",
                start = other.atTime(LocalTime.of(9, 0)).toInstant(zone),
            ),
        )
        val provider = StubCalendarEventsProvider(seed)
        val today = provider.eventsForDay(day, zone)
        assertEquals(1, today.size)
        assertEquals("A", today.first().title)
    }
}
