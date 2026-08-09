package com.lookafter.app.ui.learning

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
import androidx.compose.ui.unit.dp
import com.lookafter.app.ui.components.CalmEmptyState
import com.lookafter.app.ui.components.ElevatedSurfaceCard
import com.lookafter.app.ui.components.SectionHeader
import com.lookafter.app.ui.theme.LookAfterColors
import com.lookafter.app.ui.theme.LookAfterDimens
import com.lookafter.core.learning.LearningCard
import com.lookafter.core.learning.LearningState
import com.lookafter.core.learning.LearningTrack
import com.lookafter.core.learning.ReviewGrade
import java.time.Instant
import java.time.LocalDate
import java.time.format.DateTimeFormatter

/** Learning / spaced practice scaffold (Phase E3). */
@Composable
fun LearningScreen(
    state: LearningState,
    today: LocalDate = LocalDate.now(),
    onAddTrack: (LearningTrack) -> Unit,
    onSelectTrack: (String?) -> Unit,
    onDeleteTrack: (String) -> Unit,
    onAddCard: (LearningCard, trackId: String?) -> Unit,
    onDeleteCard: (String) -> Unit,
    onReview: (cardId: String, grade: ReviewGrade) -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var trackTitle by remember { mutableStateOf("") }
    var front by remember { mutableStateOf("") }
    var back by remember { mutableStateOf("") }
    var flipped by remember { mutableStateOf(false) }
    val selected = state.selectedTrack
    val due = state.dueCards(today, selected?.id)
    val current = due.firstOrNull()
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
                title = "Learning",
                subtitle = "${due.size} due today · light spaced practice",
            )
        }
        item {
            ElevatedSurfaceCard {
                Text("Tracks", style = MaterialTheme.typography.labelMedium, color = LookAfterColors.AccentPrimary)
                Row(
                    Modifier.fillMaxWidth().horizontalScroll(rememberScrollState())
                        .padding(top = LookAfterDimens.spacingSM),
                    horizontalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingXS),
                ) {
                    state.tracks.forEach { t ->
                        FilterChip(
                            selected = t.id == selected?.id,
                            onClick = { onSelectTrack(t.id); flipped = false },
                            label = {
                                val n = state.dueCards(today, t.id).size
                                Text("${t.title}${if (n > 0) " · $n" else ""}")
                            },
                            colors = FilterChipDefaults.filterChipColors(
                                selectedContainerColor = LookAfterColors.AccentSoft,
                                selectedLabelColor = LookAfterColors.AccentPrimary,
                            ),
                        )
                    }
                }
                OutlinedTextField(
                    value = trackTitle,
                    onValueChange = { trackTitle = it },
                    modifier = Modifier.fillMaxWidth().padding(top = LookAfterDimens.spacingSM),
                    label = { Text("New track") },
                    singleLine = true,
                )
                Row(
                    Modifier.fillMaxWidth().padding(top = LookAfterDimens.spacingSM),
                    horizontalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingSM),
                ) {
                    Button(
                        onClick = {
                            val t = trackTitle.trim()
                            if (t.isNotEmpty()) {
                                onAddTrack(LearningTrack(title = t, createdAt = Instant.now()))
                                trackTitle = ""
                            }
                        },
                        enabled = trackTitle.isNotBlank(),
                        colors = ButtonDefaults.buttonColors(containerColor = LookAfterColors.AccentPrimary),
                    ) { Text("Add track") }
                    if (selected != null && state.tracks.size > 1) {
                        TextButton(onClick = { onDeleteTrack(selected.id) }) { Text("Delete track") }
                    }
                }
            }
        }
        item {
            if (current == null) {
                CalmEmptyState(
                    title = "Caught up",
                    subtitle = "No cards due. Add a prompt below, or come back tomorrow.",
                )
            } else {
                ElevatedSurfaceCard(
                    modifier = Modifier.clickable { flipped = !flipped },
                ) {
                    Text(
                        if (flipped) "Answer · tap to hide" else "Prompt · tap to flip",
                        style = MaterialTheme.typography.labelMedium,
                        color = LookAfterColors.Focus,
                    )
                    Text(
                        if (flipped) current.back.ifBlank { "(no answer yet)" } else current.front,
                        style = MaterialTheme.typography.headlineMedium,
                        modifier = Modifier.padding(top = LookAfterDimens.spacingSM),
                    )
                    Text(
                        "Due ${current.dueOn.format(dayFmt)} · interval ${current.intervalDays}d · ease ${"%.2f".format(current.easeFactor)}",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
                    )
                    if (flipped) {
                        Row(
                            Modifier.fillMaxWidth().padding(top = LookAfterDimens.spacingSM),
                            horizontalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingXS),
                        ) {
                            listOf(
                                ReviewGrade.AGAIN to "Again",
                                ReviewGrade.HARD to "Hard",
                                ReviewGrade.GOOD to "Good",
                                ReviewGrade.EASY to "Easy",
                            ).forEach { (g, label) ->
                                Button(
                                    onClick = {
                                        onReview(current.id, g)
                                        flipped = false
                                    },
                                    modifier = Modifier.weight(1f),
                                    colors = ButtonDefaults.buttonColors(
                                        containerColor = when (g) {
                                            ReviewGrade.AGAIN -> LookAfterColors.Warning
                                            ReviewGrade.EASY -> LookAfterColors.Success
                                            else -> LookAfterColors.AccentPrimary
                                        },
                                    ),
                                    contentPadding = PaddingValues(horizontal = 4.dp, vertical = 8.dp),
                                ) { Text(label, style = MaterialTheme.typography.labelMedium) }
                            }
                        }
                    }
                }
            }
        }
        item {
            ElevatedSurfaceCard {
                Text("Add card", style = MaterialTheme.typography.labelMedium, color = LookAfterColors.AccentPrimary)
                OutlinedTextField(
                    value = front,
                    onValueChange = { front = it },
                    modifier = Modifier.fillMaxWidth().padding(top = LookAfterDimens.spacingSM),
                    label = { Text("Front (prompt)") },
                    singleLine = true,
                )
                OutlinedTextField(
                    value = back,
                    onValueChange = { back = it },
                    modifier = Modifier.fillMaxWidth().padding(top = LookAfterDimens.spacingSM),
                    label = { Text("Back (answer)") },
                    minLines = 2,
                )
                Button(
                    onClick = {
                        if (front.isBlank()) return@Button
                        onAddCard(
                            LearningCard(
                                front = front.trim(),
                                back = back.trim(),
                                dueOn = today,
                                createdAt = Instant.now(),
                            ),
                            selected?.id,
                        )
                        front = ""
                        back = ""
                    },
                    enabled = front.isNotBlank(),
                    modifier = Modifier.padding(top = LookAfterDimens.spacingSM),
                    colors = ButtonDefaults.buttonColors(containerColor = LookAfterColors.AccentPrimary),
                ) { Text("Add to ${selected?.title ?: "track"}") }
            }
        }
        val all = selected?.let { state.cardsForTrack(it.id) }.orEmpty()
        if (all.isNotEmpty()) {
            item {
                Text("In track · ${all.size}", style = MaterialTheme.typography.titleMedium)
            }
            items(all.take(20), key = { it.id }) { card ->
                ElevatedSurfaceCard {
                    Text(card.front, style = MaterialTheme.typography.titleMedium)
                    Text(
                        "Next ${card.dueOn.format(dayFmt)}",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    TextButton(onClick = { onDeleteCard(card.id) }) { Text("Delete") }
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
