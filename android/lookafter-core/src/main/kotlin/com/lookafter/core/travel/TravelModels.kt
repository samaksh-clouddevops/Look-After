package com.lookafter.core.travel

import com.lookafter.core.serialization.LocalDateSerializer
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import java.util.UUID
import kotlinx.serialization.Serializable

@Serializable
data class PackingItem(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val category: String = "General",
    val isPacked: Boolean = false,
)

@Serializable
data class TravelTrip(
    val id: String = UUID.randomUUID().toString(),
    val destination: String,
    @Serializable(with = LocalDateSerializer::class)
    val startDate: LocalDate,
    @Serializable(with = LocalDateSerializer::class)
    val endDate: LocalDate,
    val packingList: List<PackingItem> = emptyList(),
    val notes: String = "",
    val flightsOrBookings: String = "",
    /** IANA zone id e.g. America/New_York — optional scaffold. */
    val timeZoneId: String = "",
) {
    val nightCount: Int
        get() = ChronoUnit.DAYS.between(startDate, endDate).toInt().coerceAtLeast(0)

    val dayCount: Int
        get() = (nightCount + 1).coerceAtLeast(1)

    fun covers(day: LocalDate): Boolean =
        !day.isBefore(startDate) && !day.isAfter(endDate)

    val packingProgress: Pair<Int, Int>
        get() {
            val done = packingList.count { it.isPacked }
            return done to packingList.size
        }
}

@Serializable
data class TravelState(
    val trips: List<TravelTrip> = emptyList(),
    val selectedTripId: String? = null,
) {
    val selectedTrip: TravelTrip?
        get() = trips.firstOrNull { it.id == selectedTripId } ?: trips.firstOrNull()

    val upcoming: List<TravelTrip>
        get() = trips.sortedBy { it.startDate }

    companion object {
        val EMPTY = TravelState()
    }
}

sealed class TravelIntent {
    data class AddTrip(val trip: TravelTrip) : TravelIntent()
    data class UpdateTrip(val trip: TravelTrip) : TravelIntent()
    data class DeleteTrip(val id: String) : TravelIntent()
    data class SelectTrip(val id: String?) : TravelIntent()
    data class AddPackingItem(val tripId: String, val item: PackingItem) : TravelIntent()
    data class TogglePackingItem(val tripId: String, val itemId: String) : TravelIntent()
    data class DeletePackingItem(val tripId: String, val itemId: String) : TravelIntent()
    data class ReplaceState(val state: TravelState) : TravelIntent()
}

/**
 * Pure travel reducer + day packing helpers (Phase E1).
 * UI/persistence live in app layer.
 */
object TravelEngine {

    fun reduce(current: TravelState, intent: TravelIntent): TravelState = when (intent) {
        is TravelIntent.AddTrip -> {
            val trip = normalize(intent.trip)
            current.copy(
                trips = (current.trips + trip).sortedBy { it.startDate },
                selectedTripId = trip.id,
            )
        }
        is TravelIntent.UpdateTrip -> {
            val trip = normalize(intent.trip)
            current.copy(
                trips = current.trips.map { if (it.id == trip.id) trip else it }
                    .sortedBy { it.startDate },
            )
        }
        is TravelIntent.DeleteTrip -> current.copy(
            trips = current.trips.filterNot { it.id == intent.id },
            selectedTripId = current.selectedTripId?.takeIf { it != intent.id },
        )
        is TravelIntent.SelectTrip -> current.copy(selectedTripId = intent.id)
        is TravelIntent.AddPackingItem -> updateTrip(current, intent.tripId) { t ->
            t.copy(packingList = t.packingList + intent.item)
        }
        is TravelIntent.TogglePackingItem -> updateTrip(current, intent.tripId) { t ->
            t.copy(
                packingList = t.packingList.map {
                    if (it.id == intent.itemId) it.copy(isPacked = !it.isPacked) else it
                },
            )
        }
        is TravelIntent.DeletePackingItem -> updateTrip(current, intent.tripId) { t ->
            t.copy(packingList = t.packingList.filterNot { it.id == intent.itemId })
        }
        is TravelIntent.ReplaceState -> intent.state
    }

    /** Days of a trip for week-scrubber style packing (start..end inclusive). */
    fun itineraryDays(trip: TravelTrip): List<LocalDate> {
        if (trip.endDate.isBefore(trip.startDate)) return listOf(trip.startDate)
        val n = ChronoUnit.DAYS.between(trip.startDate, trip.endDate).toInt()
        return (0..n).map { trip.startDate.plusDays(it.toLong()) }
    }

    /** Default packing seed by trip length (light scaffold). */
    fun defaultPacking(nights: Int): List<PackingItem> {
        val clothes = (1..(nights.coerceAtLeast(1))).map {
            PackingItem(name = "Outfit day $it", category = "Clothing")
        }
        val base = listOf(
            PackingItem(name = "Passport / ID", category = "Documents"),
            PackingItem(name = "Phone charger", category = "Tech"),
            PackingItem(name = "Toothbrush", category = "Toiletries"),
            PackingItem(name = "Meds pouch", category = "Toiletries"),
        )
        return base + clothes
    }

    fun tripActiveOn(state: TravelState, day: LocalDate): TravelTrip? =
        state.trips.firstOrNull { it.covers(day) }

    private fun updateTrip(
        state: TravelState,
        tripId: String,
        transform: (TravelTrip) -> TravelTrip,
    ): TravelState = state.copy(
        trips = state.trips.map { if (it.id == tripId) normalize(transform(it)) else it },
    )

    private fun normalize(trip: TravelTrip): TravelTrip {
        val end = if (trip.endDate.isBefore(trip.startDate)) trip.startDate else trip.endDate
        return trip.copy(
            destination = trip.destination.trim().ifBlank { "Trip" },
            endDate = end,
            notes = trip.notes.trim(),
            flightsOrBookings = trip.flightsOrBookings.trim(),
        )
    }
}
