package com.lookafter.app.ui.insights

import androidx.compose.foundation.clickable
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
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.lookafter.app.ui.components.ElevatedSurfaceCard
import com.lookafter.app.ui.components.SectionHeader
import com.lookafter.app.ui.theme.LookAfterColors
import com.lookafter.app.ui.theme.LookAfterDimens
import com.lookafter.core.insights.InsightsSnapshot
import java.time.format.DateTimeFormatter
import kotlin.math.roundToInt

@Composable
fun InsightsScreen(
    snapshot: InsightsSnapshot,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val dayFmt = DateTimeFormatter.ofPattern("EEE")
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
                title = "Insights",
                subtitle = snapshot.headline,
            )
        }
        item {
            ElevatedSurfaceCard {
                Text(
                    "Coach read",
                    style = MaterialTheme.typography.labelMedium,
                    color = LookAfterColors.AccentPrimary,
                )
                Text(
                    snapshot.coachingLine,
                    style = MaterialTheme.typography.bodyLarge,
                    modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
                )
            }
        }
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingSM),
            ) {
                MetricCard("Done 7d", "${snapshot.completed7d}", Modifier.weight(1f))
                MetricCard(
                    "Focus",
                    "${snapshot.focusMinutes7d}m",
                    Modifier.weight(1f),
                )
                MetricCard("Streak", "${snapshot.streakDays}d", Modifier.weight(1f))
            }
        }
        item {
            ElevatedSurfaceCard {
                Text("Completion rate", style = MaterialTheme.typography.labelMedium)
                LinearProgressIndicator(
                    progress = { snapshot.completionRate7d.toFloat() },
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = LookAfterDimens.spacingSM)
                        .height(8.dp),
                    color = LookAfterColors.AccentPrimary,
                )
                Text(
                    "${(snapshot.completionRate7d * 100).roundToInt()}% · " +
                        "open ${snapshot.openNow} · parked ${snapshot.parkedNow}",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
                )
            }
        }
        item {
            ElevatedSurfaceCard {
                Text("7-day bars", style = MaterialTheme.typography.labelMedium)
                Column(
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                    modifier = Modifier.padding(top = LookAfterDimens.spacingSM),
                ) {
                    val max = (snapshot.dayBars.maxOfOrNull { it.completed } ?: 1).coerceAtLeast(1)
                    snapshot.dayBars.forEach { bar ->
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Text(
                                bar.day.format(dayFmt),
                                style = MaterialTheme.typography.labelSmall,
                                modifier = Modifier.weight(0.2f),
                            )
                            LinearProgressIndicator(
                                progress = { bar.completed.toFloat() / max.toFloat() },
                                modifier = Modifier
                                    .weight(0.6f)
                                    .height(8.dp)
                                    .padding(top = 4.dp),
                                color = LookAfterColors.Focus,
                            )
                            Text(
                                "${bar.completed}",
                                style = MaterialTheme.typography.labelSmall,
                                modifier = Modifier.weight(0.15f),
                            )
                        }
                    }
                }
            }
        }
        if (snapshot.topTags.isNotEmpty()) {
            item {
                ElevatedSurfaceCard {
                    Text("Top tags", style = MaterialTheme.typography.labelMedium)
                    Text(
                        snapshot.topTags.joinToString(" · "),
                        style = MaterialTheme.typography.titleLarge,
                        modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
                    )
                }
            }
        }
        item {
            Text(
                "Back",
                color = LookAfterColors.AccentPrimary,
                modifier = Modifier
                    .clickable(onClick = onBack)
                    .padding(top = LookAfterDimens.spacingSM),
            )
        }
    }
}

@Composable
private fun MetricCard(label: String, value: String, modifier: Modifier = Modifier) {
    ElevatedSurfaceCard(modifier = modifier) {
        Text(value, style = MaterialTheme.typography.headlineMedium)
        Text(
            label,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
