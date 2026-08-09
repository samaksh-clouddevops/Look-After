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
                    "Performance",
                    style = MaterialTheme.typography.labelMedium,
                    color = LookAfterColors.AccentPrimary,
                )
                Text(
                    snapshot.performanceLabel,
                    style = MaterialTheme.typography.displayLarge,
                    modifier = Modifier.padding(top = LookAfterDimens.spacingXXS),
                )
                LinearProgressIndicator(
                    progress = { snapshot.performanceScore.toFloat().coerceIn(0f, 1f) },
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = LookAfterDimens.spacingSM)
                        .height(8.dp),
                    color = LookAfterColors.AccentPrimary,
                )
                Text(
                    "${(snapshot.performanceScore * 100).roundToInt()} · " +
                        "${"%.1f".format(snapshot.weeklyFocusHours)}h focus · " +
                        "streak quality ${"%.1f".format(snapshot.streakQuality)}",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
                )
            }
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
                MetricCard(
                    "Done ${snapshot.windowDays}d",
                    "${snapshot.completed7d}",
                    Modifier.weight(1f),
                )
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
                        "open ${snapshot.openNow} · parked ${snapshot.parkedNow} · " +
                        "someday ${snapshot.somedayNow}",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
                )
            }
        }
        item {
            ElevatedSurfaceCard {
                Text(
                    "Board mix",
                    style = MaterialTheme.typography.labelMedium,
                    color = LookAfterColors.AccentPrimary,
                )
                Text(
                    "A ${(snapshot.anchoredShare * 100).roundToInt()}% · " +
                        "X ${(snapshot.flexibleShare * 100).roundToInt()}% · " +
                        "F ${(snapshot.fluidShare * 100).roundToInt()}% · " +
                        "high-pri open ${snapshot.highPriorityOpen}",
                    style = MaterialTheme.typography.bodyLarge,
                    modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
                )
            }
        }
        item {
            ElevatedSurfaceCard {
                Text(
                    "Recovery",
                    style = MaterialTheme.typography.labelMedium,
                    color = LookAfterColors.Health,
                )
                Text(
                    buildString {
                        append("Readiness ")
                        append(snapshot.readiness?.let { "${(it * 100).roundToInt()}%" } ?: "—")
                        snapshot.avgReadiness7d?.let {
                            append(" · 7d avg ${(it * 100).roundToInt()}% (${snapshot.readinessTrend})")
                        }
                        snapshot.avgSleepHours7d?.let {
                            append("\nSleep avg %.1fh (%s)".format(it, snapshot.sleepTrend))
                        }
                        if (snapshot.medAdherenceToday > 0) {
                            append("\nMeds today ${(snapshot.medAdherenceToday * 100).roundToInt()}%")
                        }
                    },
                    style = MaterialTheme.typography.bodyLarge,
                    modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
                )
            }
        }
        item {
            ElevatedSurfaceCard {
                Text(
                    "${snapshot.windowDays}-day bars",
                    style = MaterialTheme.typography.labelMedium,
                )
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
                                modifier = Modifier.weight(0.18f),
                            )
                            LinearProgressIndicator(
                                progress = { bar.completed.toFloat() / max.toFloat() },
                                modifier = Modifier
                                    .weight(0.52f)
                                    .height(8.dp)
                                    .padding(top = 4.dp),
                                color = LookAfterColors.Focus,
                            )
                            Text(
                                "${bar.completed} · ${bar.focusMinutes}m",
                                style = MaterialTheme.typography.labelSmall,
                                modifier = Modifier.weight(0.30f),
                            )
                        }
                    }
                }
            }
        }
        if (snapshot.tagHeat.isNotEmpty()) {
            item {
                ElevatedSurfaceCard {
                    Text(
                        "Tag heat",
                        style = MaterialTheme.typography.labelMedium,
                        color = LookAfterColors.AccentPrimary,
                    )
                    Column(
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                        modifier = Modifier.padding(top = LookAfterDimens.spacingSM),
                    ) {
                        snapshot.tagHeat.forEach { tag ->
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                Text(
                                    "#${tag.tag}",
                                    style = MaterialTheme.typography.labelSmall,
                                    modifier = Modifier.weight(0.35f),
                                )
                                LinearProgressIndicator(
                                    progress = { tag.heat.toFloat().coerceIn(0f, 1f) },
                                    modifier = Modifier
                                        .weight(0.5f)
                                        .height(8.dp)
                                        .padding(top = 4.dp),
                                    color = LookAfterColors.AccentPrimary,
                                )
                                Text(
                                    "${tag.count}",
                                    style = MaterialTheme.typography.labelSmall,
                                    modifier = Modifier.weight(0.15f),
                                )
                            }
                        }
                    }
                }
            }
        }
        if (snapshot.reviewHints.isNotEmpty()) {
            item {
                ElevatedSurfaceCard {
                    Text(
                        "Weekly review",
                        style = MaterialTheme.typography.labelMedium,
                        color = LookAfterColors.Warning,
                    )
                    snapshot.reviewHints.forEach { hint ->
                        Text(
                            "· $hint",
                            style = MaterialTheme.typography.bodyLarge,
                            modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
                        )
                    }
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
