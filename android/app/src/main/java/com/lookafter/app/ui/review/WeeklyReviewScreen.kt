package com.lookafter.app.ui.review

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.Block
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.lookafter.app.ui.theme.LookAfterColors
import com.lookafter.core.engine.LifeState
import com.lookafter.core.planning.WeeklyReviewAggregator
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.roundToInt

/**
 * Weekly debrief — visualizes [WeeklyReviewAggregator] over [LifeState.actionLogs].
 */
@Composable
fun WeeklyReviewScreen(
    state: LifeState,
    modifier: Modifier = Modifier,
) {
    val metrics = remember(state.actionLogs) {
        WeeklyReviewAggregator.aggregate(state.actionLogs)
    }
    val bounds = remember(state.currentDay) { weekBoundsLabel(state.currentDay) }

    LazyVerticalGrid(
        columns = GridCells.Fixed(2),
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 20.dp, vertical = 24.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item(span = { GridItemSpan(maxLineSpan) }) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    text = "Weekly Debrief",
                    style = MaterialTheme.typography.displayLarge,
                    color = MaterialTheme.colorScheme.onBackground,
                )
                Text(
                    text = bounds,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        item(span = { GridItemSpan(maxLineSpan) }) {
            TimeReclaimedHero(
                reclaimedHours = metrics.timeReclaimedHours,
                equilibriumScore = metrics.equilibriumScore,
            )
        }

        item {
            MetricTile(
                title = "Deep Focus",
                value = formatHours(metrics.totalFocusHours),
                caption = "Hours protected",
                icon = Icons.Outlined.AutoAwesome,
            )
        }
        item {
            MetricTile(
                title = "Sabotage",
                value = metrics.sabotageAuctionCount.toString(),
                caption = "Recovery locks",
                icon = Icons.Outlined.Block,
            )
        }
        item {
            MetricTile(
                title = "Deduplicated",
                value = metrics.supersededCount.toString(),
                caption = "Semantic collisions",
                icon = Icons.Outlined.ContentCopy,
            )
        }
        item {
            MetricTile(
                title = "Cleanly Expired",
                value = metrics.expiredCount.toString(),
                caption = "Ephemeral kills",
                icon = Icons.Outlined.Schedule,
            )
        }

        item(span = { GridItemSpan(maxLineSpan) }) {
            ExecutiveSummaryCard(
                highLoadStreakDays = state.consecutiveHighLoadDays,
                metrics = metrics,
            )
        }
    }
}

@Composable
private fun TimeReclaimedHero(
    reclaimedHours: Double,
    equilibriumScore: Double,
) {
    Card(
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.5.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                text = "Time Reclaimed",
                style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.Bottom,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    text = formatHours(reclaimedHours),
                    style = MaterialTheme.typography.displayLarge.copy(
                        fontSize = 42.sp,
                        fontWeight = FontWeight.Bold,
                        lineHeight = 48.sp,
                    ),
                    color = MaterialTheme.colorScheme.onSurface,
                )
                EquilibriumCapsule(score = equilibriumScore)
            }
            Text(
                text = "Hours returned by recovery locks & cascade hygiene",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun EquilibriumCapsule(score: Double) {
    val pct = (score * 100).roundToInt().coerceIn(0, 100)
    Box(
        modifier = Modifier
            .background(
                color = LookAfterColors.Accent.copy(alpha = 0.12f),
                shape = RoundedCornerShape(999.dp),
            )
            .padding(horizontal = 12.dp, vertical = 6.dp),
    ) {
        Text(
            text = "Eq $pct%",
            style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold),
            color = LookAfterColors.Accent,
        )
    }
}

@Composable
private fun ExecutiveSummaryCard(
    highLoadStreakDays: Int,
    metrics: WeeklyReviewAggregator.WeeklyReviewMetrics,
) {
    val summary = executiveSummary(highLoadStreakDays, metrics)
    Card(
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                text = "Executive Summary",
                style = MaterialTheme.typography.titleLarge,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                text = summary,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(2.dp))
            Text(
                text = "High-load streak: ${highLoadStreakDays.coerceAtLeast(0)} day(s)",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

private fun executiveSummary(
    streak: Int,
    metrics: WeeklyReviewAggregator.WeeklyReviewMetrics,
): String {
    val density = when {
        streak >= 4 -> "The week ran hot — $streak consecutive high-load days. Protect recovery."
        streak >= 2 -> "Moderate density: $streak high-load days in a row. Cascade is absorbing thrash."
        else -> "Load stayed contained. Room to push deep work without tipping equilibrium."
    }
    val focus = "Deep focus logged ${formatHours(metrics.totalFocusHours)}; " +
        "${metrics.supersededCount} duplicates dropped, ${metrics.expiredCount} ephemeral windows released."
    return "$density $focus"
}

private fun formatHours(hours: Double): String {
    if (hours <= 0.0) return "0h"
    val whole = hours.toInt()
    val fraction = ((hours - whole) * 10).roundToInt()
    return if (fraction == 0) "${whole}h" else "$whole.${fraction}h"
}

private fun weekBoundsLabel(currentDay: LocalDate?): String {
    val end = currentDay ?: LocalDate.now()
    val start = end.minusDays(6)
    val fmt = DateTimeFormatter.ofPattern("MMM d", Locale.US)
    return "${start.format(fmt)} – ${end.format(fmt)}"
}
