package com.lookafter.app.ui.briefing

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
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.lookafter.app.ui.components.ElevatedSurfaceCard
import com.lookafter.app.ui.components.SectionHeader
import com.lookafter.app.ui.theme.LookAfterColors
import com.lookafter.app.ui.theme.LookAfterDimens
import com.lookafter.core.brain.BrainTick
import com.lookafter.core.brain.ExecutiveBrainEngine
import com.lookafter.core.briefing.BriefingNarrativeBuilder
import com.lookafter.core.capacity.CapacityBand
import com.lookafter.core.capacity.ExecutiveCapacity
import com.lookafter.core.capacity.ExecutiveCapacityEngine
import com.lookafter.core.cycle.CycleSnapshot
import com.lookafter.core.engine.LifeState
import com.lookafter.core.health.HealthSummary
import kotlin.math.roundToInt

/** Morning briefing — narrative from WorldState + capacity + care + cycle. */
@Composable
fun BriefingScreen(
    state: LifeState,
    health: HealthSummary = HealthSummary.EMPTY,
    capacity: ExecutiveCapacity? = null,
    brainTick: BrainTick? = null,
    cycle: CycleSnapshot = CycleSnapshot(),
    onStartFocus: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val tick = brainTick ?: remember(state, health) { ExecutiveBrainEngine.tick(state, health) }
    val cap = capacity ?: remember(state, health, tick, cycle) {
        ExecutiveCapacityEngine.compute(
            state = state,
            health = health,
            world = tick.world,
            cycleModifier = cycle.capacityModifier,
            cyclePhaseLabel = cycle.phaseLabel.takeIf { cycle.trackingEnabled },
        )
    }
    val narrative = remember(state, health, tick, cap, cycle) {
        BriefingNarrativeBuilder.build(state, health, tick, cap, cycle = cycle)
    }

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(
            horizontal = LookAfterDimens.screenHorizontal,
            vertical = LookAfterDimens.spacingLG,
        ),
        verticalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingMD),
    ) {
        item {
            SectionHeader(title = narrative.greeting, subtitle = narrative.orientation)
        }
        item { CapacityCard(narrative.capacity) }
        item {
            ElevatedSurfaceCard {
                Text("Primary move", style = MaterialTheme.typography.labelMedium, color = LookAfterColors.AccentPrimary)
                Text(narrative.heroTitle, style = MaterialTheme.typography.headlineMedium, modifier = Modifier.padding(top = LookAfterDimens.spacingXXS))
                Text(
                    narrative.heroReason,
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
                )
                if (narrative.showFocusCta && onStartFocus != null) {
                    Button(
                        onClick = onStartFocus,
                        modifier = Modifier.fillMaxWidth().padding(top = LookAfterDimens.spacingSM),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = LookAfterColors.AccentPrimary,
                            contentColor = LookAfterColors.AccentOnPrimary,
                        ),
                    ) { Text(narrative.focusCtaLabel) }
                }
            }
        }
        narrative.careLine?.let { care ->
            item {
                ElevatedSurfaceCard {
                    Text("Care", style = MaterialTheme.typography.labelMedium, color = LookAfterColors.Health)
                    Text(care, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(top = LookAfterDimens.spacingXS))
                }
            }
        }
        narrative.calendarLine?.let { cal ->
            item {
                ElevatedSurfaceCard {
                    Text("Calendar", style = MaterialTheme.typography.labelMedium, color = LookAfterColors.Focus)
                    Text(cal, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(top = LookAfterDimens.spacingXS))
                }
            }
        }
        narrative.cycleLine?.let { cycleText ->
            item {
                ElevatedSurfaceCard {
                    Text("Cycle", style = MaterialTheme.typography.labelMedium, color = LookAfterColors.Health)
                    Text(
                        cycleText,
                        style = MaterialTheme.typography.bodyLarge,
                        modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
                    )
                }
            }
        }
        item {
            ElevatedSurfaceCard {
                Text("Board", style = MaterialTheme.typography.labelMedium, color = LookAfterColors.AccentPrimary)
                Text(narrative.boardLine, style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(top = LookAfterDimens.spacingXXS))
            }
        }
        item { Text("Guidance", style = MaterialTheme.typography.titleMedium) }
        items(narrative.guidance) { line ->
            ElevatedSurfaceCard {
                Text(line.eyebrow, style = MaterialTheme.typography.labelMedium, color = LookAfterColors.AccentPrimary)
                Text(line.body, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(top = LookAfterDimens.spacingXXS))
            }
        }
    }
}

@Composable
private fun CapacityCard(capacity: ExecutiveCapacity) {
    val accent = when (capacity.band) {
        CapacityBand.RECOVERY -> LookAfterColors.Warning
        CapacityBand.PROTECTIVE -> LookAfterColors.Focus
        CapacityBand.STEADY -> LookAfterColors.AccentPrimary
        CapacityBand.HIGH -> LookAfterColors.Success
    }
    ElevatedSurfaceCard {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Column(Modifier.weight(1f)) {
                Text("Capacity", style = MaterialTheme.typography.labelMedium, color = accent)
                Text(capacity.headline, style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(top = LookAfterDimens.spacingXXS))
            }
            Text("${(capacity.energyScore * 100).roundToInt()}%", style = MaterialTheme.typography.headlineMedium, color = accent)
        }
        LinearProgressIndicator(
            progress = { capacity.energyScore.toFloat().coerceIn(0f, 1f) },
            modifier = Modifier.fillMaxWidth().padding(top = LookAfterDimens.spacingSM).height(8.dp),
            color = accent,
        )
        Text(
            "Favor ~${capacity.recommendedFocusMinutes}m deep work · ≤${capacity.recommendedOpenTasks} open · ${capacity.plannedOpenMinutes}m planned",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
        )
        if (capacity.isOverCommitted) {
            Text(
                "Over committed — strip fluid before adding load.",
                style = MaterialTheme.typography.labelMedium,
                color = LookAfterColors.Warning,
                modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
            )
        }
    }
}
