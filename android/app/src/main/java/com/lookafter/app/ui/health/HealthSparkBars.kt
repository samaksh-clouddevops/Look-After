package com.lookafter.app.ui.health

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.lookafter.app.ui.components.ElevatedSurfaceCard
import com.lookafter.app.ui.theme.LookAfterDimens
import com.lookafter.core.health.HealthHistorySeries
import java.time.format.TextStyle
import java.util.Locale

/** Simple 7-day vertical bar chart for a metric series. */
@Composable
fun HealthSparkBarsCard(
    title: String,
    series: HealthHistorySeries,
    values: List<Double?>,
    barColor: Color,
    averageLabel: String,
    trendLabel: String,
    valueFormatter: (Double) -> String = { "%.1f".format(it) },
    modifier: Modifier = Modifier,
) {
    ElevatedSurfaceCard(modifier = modifier) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(title, style = MaterialTheme.typography.labelMedium, color = barColor)
            Text(
                "$averageLabel · $trendLabel",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        if (values.all { it == null } || series.days.isEmpty()) {
            Text(
                "No history yet",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = LookAfterDimens.spacingSM),
            )
            return@ElevatedSurfaceCard
        }
        val maxVal = values.mapNotNull { it }.maxOrNull()?.takeIf { it > 0 } ?: 1.0
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(120.dp)
                .padding(top = LookAfterDimens.spacingSM),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.Bottom,
        ) {
            series.days.forEachIndexed { index, point ->
                val v = values.getOrNull(index)
                val ratio = if (v != null) (v / maxVal).toFloat().coerceIn(0.04f, 1f) else 0.04f
                Column(
                    modifier = Modifier.weight(1f),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .weight(1f),
                        contentAlignment = Alignment.BottomCenter,
                    ) {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth(0.7f)
                                .fillMaxHeight(ratio)
                                .clip(RoundedCornerShape(6.dp))
                                .background(
                                    if (v != null) barColor else barColor.copy(alpha = 0.2f),
                                ),
                        )
                    }
                    Spacer(Modifier.height(4.dp))
                    Text(
                        point.day.dayOfWeek.getDisplayName(TextStyle.NARROW, Locale.getDefault()),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
        val last = values.lastOrNull { it != null }
        if (last != null) {
            Text(
                "Latest ${valueFormatter(last)}",
                style = MaterialTheme.typography.bodyLarge,
                modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
            )
        }
    }
}

/** Convenience extractors for chart values. */
object HealthChartValues {
    fun sleepHours(series: HealthHistorySeries): List<Double?> =
        series.days.map { it.sleepHours }

    fun readiness(series: HealthHistorySeries): List<Double?> =
        series.days.map { it.readinessScore?.times(100.0) }

    fun steps(series: HealthHistorySeries): List<Double?> =
        series.days.map { it.steps?.toDouble() }

    fun normalizeSteps(raw: List<Double?>): List<Double?> {
        val maxV = raw.mapNotNull { it }.maxOrNull() ?: return raw
        if (maxV <= 0) return raw
        return raw // bars already scale to max
    }

    fun stepLabel(v: Double): String =
        if (v >= 1000) "%.1fk".format(v / 1000.0) else v.toInt().toString()
}
