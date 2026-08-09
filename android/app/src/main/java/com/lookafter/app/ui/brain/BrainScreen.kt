package com.lookafter.app.ui.brain

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
import com.lookafter.app.ui.components.ElevatedSurfaceCard
import com.lookafter.app.ui.components.SectionHeader
import com.lookafter.app.ui.theme.LookAfterColors
import com.lookafter.app.ui.theme.LookAfterDimens
import com.lookafter.core.brain.BrainTick
import com.lookafter.core.brain.CognitiveLoadLevel
import com.lookafter.core.capacity.ExecutiveCapacity
import com.lookafter.core.planning.PlanMutationDiff
import com.lookafter.core.planning.PlanningHorizons
import kotlin.math.roundToInt

@Composable
fun BrainScreen(
    tick: BrainTick,
    coachTranscript: List<Pair<Boolean, String>>,
    onSendCoach: (String) -> Unit,
    onStartFocus: () -> Unit,
    onEmergencyFocus: () -> Unit = onStartFocus,
    pendingPlanSummary: String? = null,
    pendingMutationCount: Int = 0,
    pendingDiffLines: List<PlanMutationDiff.Line> = emptyList(),
    horizonDays: Int = PlanningHorizons.DEFAULT,
    onHorizonChange: (Int) -> Unit = {},
    onAcceptPlan: () -> Unit = {},
    onRejectPlan: () -> Unit = {},
    onClearConversation: () -> Unit = {},
    isStreaming: Boolean = false,
    isPlanning: Boolean = false,
    planDraftPreview: String? = null,
    capacity: ExecutiveCapacity = ExecutiveCapacity.EMPTY,
    modifier: Modifier = Modifier,
) {
    var draft by remember { mutableStateOf("") }
    val world = tick.world
    val decision = tick.decision

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(
            horizontal = LookAfterDimens.screenHorizontal,
            vertical = LookAfterDimens.spacingLG,
        ),
        verticalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingMD),
    ) {
        item { SectionHeader(title = "Brain", subtitle = "One next move. Plan the horizon.") }
        item {
            ElevatedSurfaceCard {
                Text(
                    "Planning horizon",
                    style = MaterialTheme.typography.labelMedium,
                    color = LookAfterColors.AccentPrimary,
                )
                Text(
                    "How far multi-day plans may spread work",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = LookAfterDimens.spacingXXS),
                )
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState())
                        .padding(top = LookAfterDimens.spacingSM),
                    horizontalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingXS),
                ) {
                    PlanningHorizons.OPTIONS.forEach { d ->
                        FilterChip(
                            selected = horizonDays == d,
                            onClick = { onHorizonChange(d) },
                            label = { Text("${d}d") },
                            colors = FilterChipDefaults.filterChipColors(
                                selectedContainerColor = LookAfterColors.AccentSoft,
                                selectedLabelColor = LookAfterColors.AccentPrimary,
                            ),
                        )
                    }
                }
            }
        }
        item {
            ElevatedSurfaceCard {
                Text("Hero", style = MaterialTheme.typography.labelMedium, color = LookAfterColors.AccentPrimary)
                Text(decision.heroTitle, style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(top = LookAfterDimens.spacingXXS))
                Text(decision.reason, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = LookAfterDimens.spacingXS))
                Text(decision.coachLine, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = LookAfterDimens.spacingXS))
                Button(
                    onClick = onStartFocus,
                    modifier = Modifier.fillMaxWidth().padding(top = LookAfterDimens.spacingSM),
                    colors = ButtonDefaults.buttonColors(containerColor = LookAfterColors.AccentPrimary, contentColor = LookAfterColors.AccentOnPrimary),
                ) { Text(decision.actionLabel) }
                Button(
                    onClick = onEmergencyFocus,
                    modifier = Modifier.fillMaxWidth().padding(top = LookAfterDimens.spacingXS),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = LookAfterColors.Warning,
                        contentColor = LookAfterColors.LightTextPrimary,
                    ),
                ) { Text("Emergency 10-min focus") }
            }
        }
        item {
            ElevatedSurfaceCard {
                Text("World", style = MaterialTheme.typography.labelMedium, color = LookAfterColors.AccentPrimary)
                Text(
                    "Energy " + "%.0f".format(world.currentEnergy * 100) + "% · Load " +
                        world.cognitiveLoad.name.lowercase() + " · Open " + world.openTaskCount,
                    style = MaterialTheme.typography.titleLarge,
                    modifier = Modifier.padding(top = LookAfterDimens.spacingXXS),
                )
                Text(
                    "Capacity ${world.capacityBand.label} · ~${world.recommendedFocusMinutes}m · " +
                        "pressure ${(world.openTaskPressure * 100).roundToInt()}% · " +
                        "cal ${world.calendarDensity.label}" +
                        if (world.calendarEventCount > 0) " (${world.calendarEventCount})" else "",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
                )
                Text(
                    "Board A${world.anchoredOpenCount}/X${world.flexibleOpenCount}/F${world.fluidOpenCount} · " +
                        "meds ${world.medicationRisk.label}" +
                        if (world.isOverCommitted) " · over committed" else "",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = LookAfterDimens.spacingXXS),
                )
                if (world.cognitiveLoad == CognitiveLoadLevel.OVERLOADED) {
                    Text(
                        "Overloaded — strip to one block.",
                        color = LookAfterColors.Warning,
                        style = MaterialTheme.typography.labelMedium,
                        modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
                    )
                }
            }
        }
        if (isPlanning) {
            item {
                ElevatedSurfaceCard {
                    Text(
                        "Planning…",
                        style = MaterialTheme.typography.labelMedium,
                        color = LookAfterColors.AccentPrimary,
                    )
                    Text(
                        "Streaming plan JSON · horizon ${horizonDays}d",
                        style = MaterialTheme.typography.titleLarge,
                        modifier = Modifier.padding(top = LookAfterDimens.spacingXXS),
                    )
                    Text(
                        planDraftPreview?.ifBlank { "Waiting for tokens…" }
                            ?: "Waiting for tokens…",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
                        maxLines = 6,
                    )
                }
            }
        }
        if (!pendingPlanSummary.isNullOrBlank() && pendingMutationCount > 0) {
            item {
                ElevatedSurfaceCard {
                    Text(
                        "Pending plan · review",
                        style = MaterialTheme.typography.labelMedium,
                        color = LookAfterColors.Warning,
                    )
                    Text(
                        pendingPlanSummary,
                        style = MaterialTheme.typography.titleLarge,
                        modifier = Modifier.padding(top = LookAfterDimens.spacingXXS),
                    )
                    Text(
                        "$pendingMutationCount change(s) · horizon ${horizonDays}d — nothing applied yet",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
                    )
                    if (pendingDiffLines.isNotEmpty()) {
                        Text(
                            "Diff",
                            style = MaterialTheme.typography.labelMedium,
                            color = LookAfterColors.AccentPrimary,
                            modifier = Modifier.padding(top = LookAfterDimens.spacingSM),
                        )
                        pendingDiffLines.forEach { line ->
                            Column(modifier = Modifier.padding(top = LookAfterDimens.spacingXS)) {
                                Text(
                                    "${line.kind}: ${line.summary}",
                                    style = MaterialTheme.typography.titleMedium,
                                )
                                if (line.detail.isNotBlank()) {
                                    Text(
                                        line.detail,
                                        style = MaterialTheme.typography.bodyLarge,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }
                        }
                    }
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = LookAfterDimens.spacingSM),
                        horizontalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingSM),
                    ) {
                        Button(
                            onClick = onRejectPlan,
                            modifier = Modifier.weight(1f),
                        ) { Text("Discard") }
                        Button(
                            onClick = onAcceptPlan,
                            modifier = Modifier.weight(1f),
                            colors = ButtonDefaults.buttonColors(containerColor = LookAfterColors.AccentPrimary),
                        ) { Text("Accept plan") }
                    }
                }
            }
        }
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text("Coach", style = MaterialTheme.typography.titleMedium)
                when {
                    isPlanning -> Text(
                        "planning…",
                        style = MaterialTheme.typography.labelMedium,
                        color = LookAfterColors.AccentPrimary,
                    )
                    isStreaming -> Text(
                        "streaming…",
                        style = MaterialTheme.typography.labelMedium,
                        color = LookAfterColors.AccentPrimary,
                    )
                }
            }
        }
        items(coachTranscript) { pair ->
            val isUser = pair.first
            val line = pair.second
            ElevatedSurfaceCard {
                Text(
                    if (isUser) "You" else "Look After",
                    style = MaterialTheme.typography.labelMedium,
                    color = if (isUser) MaterialTheme.colorScheme.onSurfaceVariant else LookAfterColors.AccentPrimary,
                )
                Text(
                    line.ifBlank { if (isStreaming && !isUser) "…" else line },
                    style = MaterialTheme.typography.bodyLarge,
                )
            }
        }
        item {
            val busy = isStreaming || isPlanning
            Column(verticalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingSM)) {
                OutlinedTextField(
                    value = draft,
                    onValueChange = { draft = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Plan or ask · ${horizonDays}d horizon") },
                    singleLine = true,
                    enabled = !busy,
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingSM),
                ) {
                    Button(
                        onClick = { onSendCoach(draft); draft = "" },
                        enabled = draft.trim().isNotEmpty() && !busy,
                        modifier = Modifier.weight(1f),
                        colors = ButtonDefaults.buttonColors(containerColor = LookAfterColors.AccentPrimary),
                    ) {
                        Text(
                            when {
                                isPlanning -> "Planning…"
                                isStreaming -> "Streaming…"
                                else -> "Send"
                            },
                        )
                    }
                    TextButton(
                        onClick = onClearConversation,
                        enabled = !busy && coachTranscript.isNotEmpty(),
                    ) { Text("Clear") }
                }
            }
        }
    }
}
