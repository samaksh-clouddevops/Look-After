package com.lookafter.app.ui.briefing

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.lookafter.app.ui.components.ElevatedSurfaceCard
import com.lookafter.app.ui.components.SectionHeader
import com.lookafter.app.ui.theme.LookAfterColors
import com.lookafter.app.ui.theme.LookAfterDimens
import com.lookafter.core.engine.LifeState
import com.lookafter.core.models.TaskStatus
import java.time.LocalDate
import java.time.format.DateTimeFormatter

/** Calm morning briefing surface — mirrors iOS Daily Briefing layout. */
@Composable
fun BriefingScreen(
    state: LifeState,
    modifier: Modifier = Modifier,
) {
    val active = state.activeTasks.count { it.status.isActive }
    val done = state.activeTasks.count { it.status == TaskStatus.COMPLETED }
    val day = state.currentDay ?: LocalDate.now()
    val dayLabel = day.format(DateTimeFormatter.ofPattern("EEEE, MMM d"))

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
                title = "Good day",
                subtitle = dayLabel,
            )
        }
        item {
            ElevatedSurfaceCard {
                Text(
                    text = if (active == 0) {
                        "Your board is clear. Protect the quiet."
                    } else {
                        "You have $active open · $done done today."
                    },
                    style = MaterialTheme.typography.titleLarge,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Text(
                    text = "Start with the next intentional block on Today.",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
                )
            }
        }
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingSM),
            ) {
                MetricChip(
                    icon = Icons.Outlined.Schedule,
                    label = "Open",
                    value = "$active",
                    modifier = Modifier.weight(1f),
                )
                MetricChip(
                    icon = Icons.Outlined.CheckCircle,
                    label = "Done",
                    value = "$done",
                    modifier = Modifier.weight(1f),
                )
                MetricChip(
                    icon = Icons.Outlined.Bolt,
                    label = "Focus",
                    value = "Ready",
                    modifier = Modifier.weight(1f),
                )
            }
        }
        item {
            ElevatedSurfaceCard {
                Text(
                    text = "Why now",
                    style = MaterialTheme.typography.titleMedium,
                    color = LookAfterColors.AccentPrimary,
                )
                Text(
                    text = "Look After keeps one calm source of truth. " +
                        "Complete tasks on Today; Briefing only surfaces orientation.",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
                )
            }
        }
    }
}

@Composable
private fun MetricChip(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    value: String,
    modifier: Modifier = Modifier,
) {
    ElevatedSurfaceCard(modifier = modifier) {
        Column(
            horizontalAlignment = Alignment.Start,
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Icon(icon, contentDescription = null, tint = LookAfterColors.AccentPrimary)
            Text(value, style = MaterialTheme.typography.titleLarge)
            Text(
                label,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
