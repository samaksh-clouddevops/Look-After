package com.lookafter.app.ui.cycle

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.lookafter.app.ui.components.ElevatedSurfaceCard
import com.lookafter.app.ui.components.SectionHeader
import com.lookafter.app.ui.theme.LookAfterColors
import com.lookafter.app.ui.theme.LookAfterDimens
import com.lookafter.core.cycle.CycleLogEntry
import com.lookafter.core.cycle.CycleSnapshot
import com.lookafter.core.cycle.CycleState
import java.time.LocalDate
import java.time.format.DateTimeFormatter

/** Cycle tracking scaffold (Phase E2) — local-only, capacity-aware. */
@Composable
fun CycleScreen(
    state: CycleState,
    snapshot: CycleSnapshot,
    onTrackingChange: (Boolean) -> Unit,
    onPeriodStartChange: (LocalDate?) -> Unit,
    onCycleLengthChange: (Int) -> Unit,
    onPeriodLengthChange: (Int) -> Unit,
    onAddLog: (CycleLogEntry) -> Unit,
    onDeleteLog: (String) -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var startText by remember(state.settings.lastPeriodStart) {
        mutableStateOf(state.settings.lastPeriodStart?.toString().orEmpty())
    }
    var cycleLen by remember(state.settings.averageCycleLengthDays) {
        mutableStateOf(state.settings.averageCycleLengthDays.toString())
    }
    var periodLen by remember(state.settings.averagePeriodLengthDays) {
        mutableStateOf(state.settings.averagePeriodLengthDays.toString())
    }
    var note by remember { mutableStateOf("") }
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
                title = "Cycle",
                subtitle = "Optional · stays on this device · shapes capacity gently",
            )
        }
        item {
            ElevatedSurfaceCard {
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text("Track cycle", style = MaterialTheme.typography.titleLarge)
                        Text(
                            "Off by default. When on, phase adjusts energy guidance.",
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Switch(
                        checked = state.settings.trackingEnabled,
                        onCheckedChange = onTrackingChange,
                        colors = SwitchDefaults.colors(checkedTrackColor = LookAfterColors.AccentPrimary),
                    )
                }
            }
        }
        if (state.settings.trackingEnabled) {
            item {
                ElevatedSurfaceCard {
                    Text("Today", style = MaterialTheme.typography.labelMedium, color = LookAfterColors.Health)
                    Text(
                        snapshot.phaseLabel + (snapshot.dayInCycle?.let { " · day $it" } ?: ""),
                        style = MaterialTheme.typography.headlineMedium,
                        modifier = Modifier.padding(top = LookAfterDimens.spacingXXS),
                    )
                    Text(
                        snapshot.coachingHint,
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
                    )
                }
            }
            item {
                ElevatedSurfaceCard {
                    Text("Period start", style = MaterialTheme.typography.titleMedium)
                    OutlinedTextField(
                        value = startText,
                        onValueChange = { startText = it },
                        modifier = Modifier.fillMaxWidth().padding(top = LookAfterDimens.spacingSM),
                        label = { Text("yyyy-MM-dd") },
                        singleLine = true,
                    )
                    OutlinedTextField(
                        value = cycleLen,
                        onValueChange = { cycleLen = it.filter(Char::isDigit).take(2) },
                        modifier = Modifier.fillMaxWidth().padding(top = LookAfterDimens.spacingSM),
                        label = { Text("Cycle length (days)") },
                        singleLine = true,
                    )
                    OutlinedTextField(
                        value = periodLen,
                        onValueChange = { periodLen = it.filter(Char::isDigit).take(2) },
                        modifier = Modifier.fillMaxWidth().padding(top = LookAfterDimens.spacingSM),
                        label = { Text("Period length (days)") },
                        singleLine = true,
                    )
                    Button(
                        onClick = {
                            val start = startText.trim().takeIf { it.isNotEmpty() }
                                ?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
                            onPeriodStartChange(start)
                            cycleLen.toIntOrNull()?.let(onCycleLengthChange)
                            periodLen.toIntOrNull()?.let(onPeriodLengthChange)
                        },
                        modifier = Modifier.padding(top = LookAfterDimens.spacingSM),
                        colors = ButtonDefaults.buttonColors(containerColor = LookAfterColors.AccentPrimary),
                    ) { Text("Save settings") }
                }
            }
            item {
                ElevatedSurfaceCard {
                    Text("Log today", style = MaterialTheme.typography.titleMedium)
                    OutlinedTextField(
                        value = note,
                        onValueChange = { note = it },
                        modifier = Modifier.fillMaxWidth().padding(top = LookAfterDimens.spacingSM),
                        label = { Text("Note (optional)") },
                        singleLine = true,
                    )
                    Row(
                        Modifier.fillMaxWidth().padding(top = LookAfterDimens.spacingSM),
                        horizontalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingSM),
                    ) {
                        Button(
                            onClick = {
                                onAddLog(
                                    CycleLogEntry(
                                        date = LocalDate.now(),
                                        note = note.trim(),
                                        isPeriodDay = false,
                                    ),
                                )
                                note = ""
                            },
                            modifier = Modifier.weight(1f),
                        ) { Text("Log") }
                        Button(
                            onClick = {
                                val today = LocalDate.now()
                                onPeriodStartChange(today)
                                onAddLog(CycleLogEntry(date = today, note = note.trim(), isPeriodDay = true))
                                note = ""
                            },
                            modifier = Modifier.weight(1f),
                            colors = ButtonDefaults.buttonColors(containerColor = LookAfterColors.Health),
                        ) { Text("Period start") }
                    }
                }
            }
            items(state.logs.take(12), key = { it.id }) { entry ->
                ElevatedSurfaceCard {
                    Text(
                        entry.date.format(dayFmt) + if (entry.isPeriodDay) " · period" else "",
                        style = MaterialTheme.typography.labelMedium,
                        color = LookAfterColors.AccentPrimary,
                    )
                    if (entry.note.isNotBlank()) {
                        Text(entry.note, style = MaterialTheme.typography.bodyLarge)
                    }
                    Text(
                        "Remove",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.labelMedium,
                        modifier = Modifier
                            .clickable { onDeleteLog(entry.id) }
                            .padding(top = LookAfterDimens.spacingXS),
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
