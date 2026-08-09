package com.lookafter.app.ui.travel

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.lookafter.app.ui.components.CalmEmptyState
import com.lookafter.app.ui.components.ElevatedSurfaceCard
import com.lookafter.app.ui.components.SectionHeader
import com.lookafter.app.ui.theme.LookAfterColors
import com.lookafter.app.ui.theme.LookAfterDimens
import com.lookafter.core.travel.PackingItem
import com.lookafter.core.travel.TravelEngine
import com.lookafter.core.travel.TravelState
import com.lookafter.core.travel.TravelTrip
import java.time.LocalDate
import java.time.format.DateTimeFormatter

/**
 * Travel module scaffold (Phase E1) — trips, packing, day strip, open on Today.
 */
@Composable
fun TravelScreen(
    state: TravelState,
    onAddTrip: (TravelTrip) -> Unit,
    onDeleteTrip: (String) -> Unit,
    onSelectTrip: (String?) -> Unit,
    onTogglePacking: (tripId: String, itemId: String) -> Unit,
    onAddPacking: (tripId: String, item: PackingItem) -> Unit,
    onOpenDayOnToday: (LocalDate) -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var showCreate by remember { mutableStateOf(false) }
    var packDraft by remember { mutableStateOf("") }
    val selected = state.selectedTrip
    val dayFmt = DateTimeFormatter.ofPattern("MMM d")

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(
            horizontal = LookAfterDimens.screenHorizontal,
            vertical = LookAfterDimens.spacingLG,
        ),
        verticalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingMD),
    ) {
        item {
            SectionHeader(
                title = "Travel",
                subtitle = "Trips, packing, open a travel day on Today",
            )
        }
        if (showCreate) {
            item {
                CreateTripCard(
                    onCancel = { showCreate = false },
                    onSave = { trip ->
                        onAddTrip(trip)
                        showCreate = false
                    },
                )
            }
        } else {
            item {
                Button(
                    onClick = { showCreate = true },
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.buttonColors(containerColor = LookAfterColors.AccentPrimary),
                ) { Text("New trip") }
            }
        }
        if (state.trips.isEmpty() && !showCreate) {
            item {
                CalmEmptyState(
                    title = "No trips yet",
                    subtitle = "Add a destination and dates. We’ll seed a light packing list.",
                    actionLabel = "New trip",
                    onAction = { showCreate = true },
                )
            }
        }
        items(state.upcoming, key = { it.id }) { trip ->
            val sel = trip.id == selected?.id
            ElevatedSurfaceCard(
                modifier = Modifier.clickable { onSelectTrip(trip.id) },
            ) {
                Text(
                    if (sel) "Selected" else "Trip",
                    style = MaterialTheme.typography.labelMedium,
                    color = LookAfterColors.AccentPrimary,
                )
                Text(trip.destination, style = MaterialTheme.typography.titleLarge)
                Text(
                    "${trip.startDate.format(dayFmt)} – ${trip.endDate.format(dayFmt)} · ${trip.dayCount}d",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                val (packed, total) = trip.packingProgress
                if (total > 0) {
                    Text(
                        "Packed $packed / $total",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                TextButton(onClick = { onDeleteTrip(trip.id) }) { Text("Delete") }
            }
        }
        selected?.let { trip ->
            item {
                ElevatedSurfaceCard {
                    Text("Itinerary days", style = MaterialTheme.typography.labelMedium, color = LookAfterColors.Focus)
                    Text(
                        "Open a day on the Today board (timezone packing scaffold).",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .horizontalScroll(rememberScrollState())
                            .padding(top = LookAfterDimens.spacingSM),
                        horizontalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingXS),
                    ) {
                        TravelEngine.itineraryDays(trip).forEach { d ->
                            FilterChip(
                                selected = false,
                                onClick = { onOpenDayOnToday(d) },
                                label = { Text(d.format(DateTimeFormatter.ofPattern("EEE d"))) },
                                colors = FilterChipDefaults.filterChipColors(
                                    selectedContainerColor = LookAfterColors.AccentSoft,
                                ),
                            )
                        }
                    }
                }
            }
            item {
                ElevatedSurfaceCard {
                    Text("Packing", style = MaterialTheme.typography.labelMedium, color = LookAfterColors.AccentPrimary)
                    OutlinedTextField(
                        value = packDraft,
                        onValueChange = { packDraft = it },
                        modifier = Modifier.fillMaxWidth().padding(top = LookAfterDimens.spacingSM),
                        label = { Text("Add item") },
                        singleLine = true,
                    )
                    Button(
                        onClick = {
                            val name = packDraft.trim()
                            if (name.isNotEmpty()) {
                                onAddPacking(trip.id, PackingItem(name = name))
                                packDraft = ""
                            }
                        },
                        enabled = packDraft.isNotBlank(),
                        modifier = Modifier.padding(top = LookAfterDimens.spacingSM),
                        colors = ButtonDefaults.buttonColors(containerColor = LookAfterColors.AccentPrimary),
                    ) { Text("Add") }
                }
            }
            items(trip.packingList, key = { it.id }) { item ->
                ElevatedSurfaceCard(modifier = Modifier.clickable { onTogglePacking(trip.id, item.id) }) {
                    Text(
                        if (item.isPacked) "Packed" else item.category,
                        style = MaterialTheme.typography.labelMedium,
                        color = if (item.isPacked) LookAfterColors.Success else LookAfterColors.AccentPrimary,
                    )
                    Text(
                        item.name,
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                }
            }
        }
        item {
            Text(
                "Back",
                color = LookAfterColors.AccentPrimary,
                modifier = Modifier.clickable(onClick = onBack).padding(top = LookAfterDimens.spacingSM),
            )
        }
    }
}

@Composable
private fun CreateTripCard(onCancel: () -> Unit, onSave: (TravelTrip) -> Unit) {
    var destination by remember { mutableStateOf("") }
    var startText by remember { mutableStateOf(LocalDate.now().toString()) }
    var nightsText by remember { mutableStateOf("3") }
    ElevatedSurfaceCard {
        Text("New trip", style = MaterialTheme.typography.titleMedium)
        OutlinedTextField(
            value = destination,
            onValueChange = { destination = it },
            modifier = Modifier.fillMaxWidth().padding(top = LookAfterDimens.spacingSM),
            label = { Text("Destination") },
            singleLine = true,
        )
        OutlinedTextField(
            value = startText,
            onValueChange = { startText = it },
            modifier = Modifier.fillMaxWidth().padding(top = LookAfterDimens.spacingSM),
            label = { Text("Start (yyyy-MM-dd)") },
            singleLine = true,
        )
        OutlinedTextField(
            value = nightsText,
            onValueChange = { nightsText = it.filter(Char::isDigit).take(2) },
            modifier = Modifier.fillMaxWidth().padding(top = LookAfterDimens.spacingSM),
            label = { Text("Nights") },
            singleLine = true,
        )
        Row(
            Modifier.fillMaxWidth().padding(top = LookAfterDimens.spacingSM),
            horizontalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingSM),
        ) {
            TextButton(onClick = onCancel) { Text("Cancel") }
            Button(
                onClick = {
                    val start = runCatching { LocalDate.parse(startText.trim()) }.getOrElse { LocalDate.now() }
                    val nights = nightsText.toIntOrNull()?.coerceIn(0, 30) ?: 3
                    val end = start.plusDays(nights.toLong())
                    val packing = TravelEngine.defaultPacking(nights)
                    onSave(
                        TravelTrip(
                            destination = destination.trim().ifBlank { "Trip" },
                            startDate = start,
                            endDate = end,
                            packingList = packing,
                        ),
                    )
                },
                colors = ButtonDefaults.buttonColors(containerColor = LookAfterColors.AccentPrimary),
            ) { Text("Save") }
        }
    }
}
