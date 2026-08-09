package com.lookafter.app.ui.brain

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.lookafter.app.ui.components.ElevatedSurfaceCard
import com.lookafter.app.ui.theme.LookAfterColors
import com.lookafter.app.ui.theme.LookAfterDimens
import com.lookafter.core.brain.CoachHistoryEntry
import com.lookafter.core.brain.CoachHistoryKind
import com.lookafter.core.brain.CoachHistoryState
import java.time.ZoneId
import java.time.format.DateTimeFormatter

@Composable
fun CoachHistorySection(
    history: CoachHistoryState,
    onPin: (id: String, pinned: Boolean) -> Unit,
    onRemove: (id: String) -> Unit,
    onClearUnpinned: () -> Unit,
    onPinCurrentHero: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val pinned = history.pinned
    val recent = history.recent.filterNot { it.pinned }.take(8)

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingSM),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("History", style = MaterialTheme.typography.titleMedium)
            Row {
                TextButton(onClick = onPinCurrentHero) { Text("Pin hero") }
                if (recent.isNotEmpty()) {
                    TextButton(onClick = onClearUnpinned) { Text("Clear") }
                }
            }
        }

        if (pinned.isEmpty() && recent.isEmpty()) {
            ElevatedSurfaceCard {
                Text(
                    "No pinned decisions yet",
                    style = MaterialTheme.typography.titleMedium,
                )
                Text(
                    "Pin “why this hero” moments so they survive chat clear.",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
                )
            }
            return
        }

        if (pinned.isNotEmpty()) {
            Text(
                "Pinned",
                style = MaterialTheme.typography.labelMedium,
                color = LookAfterColors.AccentPrimary,
            )
            pinned.forEach { entry ->
                HistoryCard(entry, onPin, onRemove)
            }
        }
        if (recent.isNotEmpty()) {
            Text(
                "Recent",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
            )
            recent.forEach { entry ->
                HistoryCard(entry, onPin, onRemove)
            }
        }
    }
}

@Composable
private fun HistoryCard(
    entry: CoachHistoryEntry,
    onPin: (id: String, pinned: Boolean) -> Unit,
    onRemove: (id: String) -> Unit,
) {
    ElevatedSurfaceCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.Top,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    kindLabel(entry.kind),
                    style = MaterialTheme.typography.labelMedium,
                    color = LookAfterColors.AccentPrimary,
                )
                Text(
                    entry.title,
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.padding(top = LookAfterDimens.spacingXXS),
                )
                if (entry.body.isNotBlank()) {
                    Text(
                        entry.body,
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
                    )
                }
                Text(
                    formatTime(entry),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = LookAfterDimens.spacingXXS),
                )
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(
                    if (entry.pinned) "Unpin" else "Pin",
                    color = LookAfterColors.AccentPrimary,
                    style = MaterialTheme.typography.labelMedium,
                    modifier = Modifier
                        .clickable { onPin(entry.id, !entry.pinned) }
                        .padding(4.dp),
                )
                Text(
                    "Remove",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    style = MaterialTheme.typography.labelMedium,
                    modifier = Modifier
                        .clickable { onRemove(entry.id) }
                        .padding(4.dp),
                )
            }
        }
    }
}

private fun kindLabel(kind: CoachHistoryKind): String = when (kind) {
    CoachHistoryKind.HERO_DECISION -> "Why this hero"
    CoachHistoryKind.COACH_REPLY -> "Coach"
    CoachHistoryKind.PLAN_ACCEPTED -> "Plan · accepted"
    CoachHistoryKind.PLAN_DISCARDED -> "Plan · discarded"
    CoachHistoryKind.NOTE -> "Note"
}

private val timeFmt: DateTimeFormatter =
    DateTimeFormatter.ofPattern("MMM d · h:mm a")

private fun formatTime(entry: CoachHistoryEntry): String {
    if (entry.at.epochSecond <= 0) return ""
    return runCatching {
        entry.at.atZone(ZoneId.systemDefault()).format(timeFmt)
    }.getOrDefault("")
}
