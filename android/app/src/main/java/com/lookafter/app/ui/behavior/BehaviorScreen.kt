package com.lookafter.app.ui.behavior

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.LinearProgressIndicator
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
import androidx.compose.ui.unit.dp
import com.lookafter.app.ui.components.CalmEmptyState
import com.lookafter.app.ui.components.ElevatedSurfaceCard
import com.lookafter.app.ui.components.SectionHeader
import com.lookafter.app.ui.theme.LookAfterColors
import com.lookafter.app.ui.theme.LookAfterDimens
import com.lookafter.core.behavior.BehaviorEngine
import com.lookafter.core.behavior.BehaviorState
import com.lookafter.core.behavior.Habit
import com.lookafter.core.behavior.HabitCadence
import java.time.Instant
import java.time.LocalDate
import kotlin.math.roundToInt

/** Behavior / habits scaffold (Phase E5). */
@Composable
fun BehaviorScreen(
    state: BehaviorState,
    today: LocalDate = LocalDate.now(),
    onAddHabit: (Habit) -> Unit,
    onToggle: (id: String) -> Unit,
    onArchive: (id: String) -> Unit,
    onDelete: (id: String) -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var title by remember { mutableStateOf("") }
    var cadence by remember { mutableStateOf(HabitCadence.DAILY) }
    val due = state.dueToday(today)
    val done = state.doneToday(today)
    val active = state.active

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
                title = "Behavior",
                subtitle = "${done.size} done · ${due.size} open today",
            )
        }
        item {
            ElevatedSurfaceCard {
                Text("New habit", style = MaterialTheme.typography.labelMedium, color = LookAfterColors.AccentPrimary)
                OutlinedTextField(
                    value = title,
                    onValueChange = { title = it },
                    modifier = Modifier.fillMaxWidth().padding(top = LookAfterDimens.spacingSM),
                    label = { Text("Title") },
                    singleLine = true,
                )
                Row(
                    Modifier.fillMaxWidth().horizontalScroll(rememberScrollState())
                        .padding(top = LookAfterDimens.spacingSM),
                    horizontalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingXS),
                ) {
                    HabitCadence.entries.forEach { c ->
                        FilterChip(
                            selected = cadence == c,
                            onClick = { cadence = c },
                            label = { Text(c.label) },
                            colors = FilterChipDefaults.filterChipColors(
                                selectedContainerColor = LookAfterColors.AccentSoft,
                                selectedLabelColor = LookAfterColors.AccentPrimary,
                            ),
                        )
                    }
                }
                Button(
                    onClick = {
                        val t = title.trim()
                        if (t.isEmpty()) return@Button
                        onAddHabit(
                            Habit(
                                title = t,
                                cadence = cadence,
                                createdAt = Instant.now(),
                            ),
                        )
                        title = ""
                    },
                    enabled = title.isNotBlank(),
                    modifier = Modifier.padding(top = LookAfterDimens.spacingSM),
                    colors = ButtonDefaults.buttonColors(containerColor = LookAfterColors.AccentPrimary),
                ) { Text("Add habit") }
            }
        }
        if (active.isEmpty()) {
            item {
                CalmEmptyState(
                    title = "No habits yet",
                    subtitle = "Start small — one daily or weekday loop. Check in when it happens.",
                    actionLabel = null,
                    onAction = null,
                )
            }
        } else {
            items(active, key = { it.id }) { habit ->
                val doneToday = habit.isDoneOn(today)
                val rate = BehaviorEngine.completionRate(habit, windowDays = 7, end = today)
                ElevatedSurfaceCard(
                    modifier = Modifier.clickable { onToggle(habit.id) },
                ) {
                    Text(
                        if (doneToday) "Done today · ${habit.cadence.label}"
                        else "Tap to check in · ${habit.cadence.label}",
                        style = MaterialTheme.typography.labelMedium,
                        color = if (doneToday) LookAfterColors.Success else LookAfterColors.AccentPrimary,
                    )
                    Text(habit.title, style = MaterialTheme.typography.titleLarge)
                    Text(
                        "Streak ${habit.currentStreak} · best ${habit.bestStreak} · 7d ${(rate * 100).roundToInt()}%",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = LookAfterDimens.spacingXXS),
                    )
                    LinearProgressIndicator(
                        progress = { rate.toFloat().coerceIn(0f, 1f) },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = LookAfterDimens.spacingSM)
                            .height(8.dp),
                        color = LookAfterColors.AccentPrimary,
                    )
                    Row(
                        Modifier.fillMaxWidth().padding(top = LookAfterDimens.spacingSM),
                        horizontalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingSM),
                    ) {
                        TextButton(onClick = { onToggle(habit.id) }) {
                            Text(if (doneToday) "Undo" else "Check in")
                        }
                        TextButton(onClick = { onArchive(habit.id) }) { Text("Archive") }
                        TextButton(onClick = { onDelete(habit.id) }) { Text("Delete") }
                    }
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
