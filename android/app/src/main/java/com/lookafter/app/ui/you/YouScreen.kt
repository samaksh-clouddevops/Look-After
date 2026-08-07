package com.lookafter.app.ui.you

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.Insights
import androidx.compose.material.icons.outlined.Medication
import androidx.compose.material.icons.outlined.Science
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import com.lookafter.app.ui.components.ElevatedSurfaceCard
import com.lookafter.app.ui.components.SectionHeader
import com.lookafter.app.ui.theme.LookAfterColors
import com.lookafter.app.ui.theme.LookAfterDimens
import com.lookafter.core.engine.LifeState
import com.lookafter.core.health.HealthSummary
import kotlin.math.roundToInt

/** Profile / settings hub — iOS "You" tab parity. */
@Composable
fun YouScreen(
    state: LifeState,
    health: HealthSummary = HealthSummary.EMPTY,
    onOpenReview: () -> Unit,
    onOpenSimulation: () -> Unit,
    onOpenMedication: () -> Unit,
    onOpenHealth: () -> Unit = {},
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
                title = "You",
                subtitle = "Identity, review, and experiments.",
            )
        }
        item {
            ElevatedSurfaceCard {
                Text(
                    text = "Life state",
                    style = MaterialTheme.typography.labelMedium,
                    color = LookAfterColors.AccentPrimary,
                )
                Text(
                    text = "${state.activeTasks.size} active · " +
                        "${state.parkedQueue.size} parked · " +
                        "${state.somedayVault.size} someday",
                    style = MaterialTheme.typography.titleLarge,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.padding(top = LookAfterDimens.spacingXXS),
                )
            }
        }
        item {
            val medCount = state.medications.size
            val adh = (state.medicationAdherenceRate * 100).roundToInt()
            YouRow(
                icon = Icons.Outlined.Medication,
                title = "Medication",
                subtitle = if (medCount == 0) {
                    "Track meds and supplements"
                } else {
                    "$medCount configured · $adh% today"
                },
                onClick = onOpenMedication,
            )
        }
        item {
            YouRow(
                icon = Icons.Outlined.FavoriteBorder,
                title = "Health",
                subtitle = if (health.readinessScore == null) {
                    "Connect readiness signals"
                } else {
                    "Readiness ${health.readinessLabel}"
                },
                onClick = onOpenHealth,
            )
        }
        item {
            YouRow(
                icon = Icons.Outlined.Insights,
                title = "Weekly Review",
                subtitle = "Metrics and cascade history",
                onClick = onOpenReview,
            )
        }
        item {
            YouRow(
                icon = Icons.Outlined.Science,
                title = "What-If Simulation",
                subtitle = "Dry-run a meeting before committing",
                onClick = onOpenSimulation,
            )
        }
        item {
            YouRow(
                icon = Icons.Outlined.Settings,
                title = "Settings",
                subtitle = "Notifications, focus, and profile",
                onClick = { /* Phase shell — wire preferences next */ },
            )
        }
    }
}

@Composable
private fun YouRow(
    icon: ImageVector,
    title: String,
    subtitle: String,
    onClick: () -> Unit,
) {
    ElevatedSurfaceCard(
        modifier = Modifier.clickable(onClick = onClick),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingSM),
        ) {
            Icon(icon, contentDescription = null, tint = LookAfterColors.AccentPrimary)
            Column(modifier = Modifier.weight(1f)) {
                Text(title, style = MaterialTheme.typography.titleLarge)
                Text(
                    subtitle,
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Icon(
                Icons.AutoMirrored.Outlined.KeyboardArrowRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
