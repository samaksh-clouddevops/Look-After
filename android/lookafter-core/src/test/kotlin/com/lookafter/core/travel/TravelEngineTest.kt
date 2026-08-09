package com.lookafter.core.travel

import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class TravelEngineTest {

    private val start = LocalDate.of(2026, 9, 1)

    @Test
    fun addTripSelectsAndNormalizesDates() {
        var state = TravelState.EMPTY
        val trip = TravelTrip(
            destination = "  Lisbon  ",
            startDate = start,
            endDate = start.minusDays(1), // inverted → clamp
            packingList = TravelEngine.defaultPacking(2),
        )
        state = TravelEngine.reduce(state, TravelIntent.AddTrip(trip))
        assertEquals(1, state.trips.size)
        assertEquals("Lisbon", state.trips.single().destination)
        assertEquals(start, state.trips.single().endDate)
        assertEquals(state.trips.single().id, state.selectedTripId)
        assertTrue(state.trips.single().packingList.size >= 4)
    }

    @Test
    fun itineraryDaysInclusive() {
        val trip = TravelTrip(destination = "NYC", startDate = start, endDate = start.plusDays(2))
        val days = TravelEngine.itineraryDays(trip)
        assertEquals(3, days.size)
        assertEquals(start, days.first())
        assertEquals(start.plusDays(2), days.last())
    }

    @Test
    fun packingToggleAndActiveOnDay() {
        var state = TravelEngine.reduce(
            TravelState.EMPTY,
            TravelIntent.AddTrip(
                TravelTrip(
                    id = "t1",
                    destination = "Rome",
                    startDate = start,
                    endDate = start.plusDays(3),
                    packingList = listOf(PackingItem(id = "p1", name = "Passport")),
                ),
            ),
        )
        state = TravelEngine.reduce(state, TravelIntent.TogglePackingItem("t1", "p1"))
        assertTrue(state.trips.single().packingList.single().isPacked)
        assertEquals("Rome", TravelEngine.tripActiveOn(state, start.plusDays(1))?.destination)
        assertEquals(null, TravelEngine.tripActiveOn(state, start.minusDays(1)))
    }
}
