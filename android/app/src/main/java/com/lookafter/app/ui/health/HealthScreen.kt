package com.lookafter.app.ui.health

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.lookafter.app.ui.components.ElevatedSurfaceCard
import com.lookafter.app.ui.components.SectionHeader
import com.lookafter.app.ui.theme.LookAfterColors
import com.lookafter.app.ui.theme.LookAfterDimens
import com.lookafter.core.health.HealthHistorySeries
import com.lookafter.core.health.HealthSummary
import com.lookafter.core.health.RollingHealthAverages
import kotlin.math.roundToInt

/** Health readiness surface — snapshot + 7-day charts (Phase D1). */
@Composable
fun HealthScreen(
    summary: HealthSummary,
    permissionGranted: Boolean,
    onPermissionChange: (Boolean) -> Unit,
    onRefresh: () -> Unit,
    onBack: () -> Unit,
    history: HealthHistorySeries = HealthHistorySeries.EMPTY,
    rolling: RollingHealthAverages = RollingHealthAverages(),
    usingDemo: Boolean = true,
    modifier: Modifier = Modifier,
) {
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
                title = "Health",
                subtitle = "Readiness, sleep, and 7-day trends.",
            )
        }
        item {
            ElevatedSurfaceCard {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = "Health Connect",
                            style = MaterialTheme.typography.titleLarge,
                        )
                        Text(
                            text = when {
                                !permissionGranted -> "Grant access to load readiness"
                                usingDemo -> "Using demo history · ${history.sourceLabel}"
                                else -> "Live history · ${history.sourceLabel}"
                            },
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Switch(
                        checked = permissionGranted,
                        onCheckedChange = onPermissionChange,
                        colors = SwitchDefaults.colors(
                            checkedTrackColor = LookAfterColors.AccentPrimary,
                        ),
                    )
                }
            }
        }
        item {
            ElevatedSurfaceCard {
                Text(
                    text = "Readiness",
                    style = MaterialTheme.typography.labelMedium,
                    color = LookAfterColors.Health,
                )
                Text(
                    text = summary.readinessLabel,
                    style = MaterialTheme.typography.displayLarge,
                    modifier = Modifier.padding(top = LookAfterDimens.spacingXXS),
                )
                rolling.readinessScore?.let { avg ->
                    Text(
                        "7-day avg ${(avg * 100).roundToInt()}% · trend ${rolling.readinessTrendLabel}",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
                    )
                }
            }
        }
        item {
            HealthSparkBarsCard(
                title = "Sleep (h)",
                series = history,
                values = HealthChartValues.sleepHours(history),
                barColor = LookAfterColors.Focus,
                averageLabel = rolling.sleepHours?.let { "avg %.1fh".format(it) } ?: "avg —",
                trendLabel = rolling.sleepTrendLabel,
                valueFormatter = { "%.1fh".format(it) },
            )
        }
        item {
            HealthSparkBarsCard(
                title = "Readiness (%)",
                series = history,
                values = HealthChartValues.readiness(history),
                barColor = LookAfterColors.Health,
                averageLabel = rolling.readinessScore?.let { "avg ${(it * 100).roundToInt()}%" } ?: "avg —",
                trendLabel = rolling.readinessTrendLabel,
                valueFormatter = { "${it.roundToInt()}%" },
            )
        }
        item {
            HealthSparkBarsCard(
                title = "Steps",
                series = history,
                values = HealthChartValues.steps(history),
                barColor = LookAfterColors.AccentPrimary,
                averageLabel = rolling.steps?.let { "avg $it" } ?: "avg —",
                trendLabel = "7d",
                valueFormatter = HealthChartValues::stepLabel,
            )
        }
        item {
            MetricRow("Sleep today", summary.sleepHours?.let { "%.1f h".format(it) } ?: "—")
        }
        item {
            MetricRow(
                "Resting HR",
                summary.restingHeartRate?.let { "${it.toInt()} bpm" } ?: "—",
            )
        }
        item {
            MetricRow("HRV (SDNN)", summary.hrvSdnn?.let { "${it.toInt()} ms" } ?: "—")
        }
        item {
            MetricRow("Steps today", summary.steps?.toString() ?: "—")
        }
        item {
            MetricRow(
                "Active energy",
                summary.activeEnergyKcal?.let { "${it.toInt()} kcal" } ?: "—",
            )
        }
        item {
            Button(
                onClick = onRefresh,
                colors = ButtonDefaults.buttonColors(
                    containerColor = LookAfterColors.AccentPrimary,
                    contentColor = LookAfterColors.AccentOnPrimary,
                ),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Refresh")
            }
        }
        item {
            Text(
                text = "Back",
                style = MaterialTheme.typography.labelMedium,
                color = LookAfterColors.AccentPrimary,
                modifier = Modifier
                    .clickable(onClick = onBack)
                    .padding(top = LookAfterDimens.spacingSM),
            )
        }
    }
}

@Composable
private fun MetricRow(label: String, value: String) {
    ElevatedSurfaceCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(label, style = MaterialTheme.typography.bodyLarge)
            Text(value, style = MaterialTheme.typography.titleLarge)
        }
    }
}
