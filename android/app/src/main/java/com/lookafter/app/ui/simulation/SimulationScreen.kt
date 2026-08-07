package com.lookafter.app.ui.simulation

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.lookafter.app.ui.timeline.TimelineTaskCard
import com.lookafter.core.engine.LifeState
import com.lookafter.core.engine.LookAfterIntent
import com.lookafter.core.models.LifeTask
import com.lookafter.core.simulation.SimulationEngine
import com.lookafter.core.simulation.SimulationImpactReport
import com.lookafter.core.simulation.SimulationResult
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

private val SandboxViolet = Color(0xFF2E1065)
private val SandboxSurface = Color(0xFF3B0764)
private val SandboxOn = Color(0xFFF5F3FF)
private val SandboxMuted = Color(0xFFC4B5FD)
private val WarningAmber = Color(0xFFFBBF24)
private val HypoBorder = Color(0xFFA78BFA)

/**
 * Dry-run sandbox. Does NOT read LifeEngine — receives [baselineState] + hypotheticals,
 * runs [SimulationEngine] locally, and only commits via [onCommit].
 */
@Composable
fun SimulationScreen(
    baselineState: LifeState,
    hypotheticalTasks: List<LifeTask>,
    onCommit: (LookAfterIntent.CommitHypotheticalTasks) -> Unit,
    onDiscard: () -> Unit,
    modifier: Modifier = Modifier,
    now: Instant = Instant.now(),
    zone: ZoneId = ZoneId.systemDefault(),
) {
    val result: SimulationResult = remember(baselineState, hypotheticalTasks, now) {
        SimulationEngine.runSimulation(
            baselineState = baselineState,
            hypotheticalTasks = hypotheticalTasks,
            now = now,
            zone = zone,
        )
    }
    val tasks = result.simulatedState.activeTasks
    val day = result.simulatedState.currentDay ?: LocalDate.now(zone)

    Scaffold(
        modifier = modifier.fillMaxSize(),
        containerColor = SandboxViolet,
        bottomBar = {
            ActionFooter(
                onDiscard = onDiscard,
                onCommit = {
                    onCommit(
                        LookAfterIntent.CommitHypotheticalTasks(
                            tasks = hypotheticalTasks,
                            day = day,
                            now = now,
                            zone = zone,
                        ),
                    )
                },
            )
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize(),
            contentPadding = PaddingValues(horizontal = 20.dp, vertical = 20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item(key = "header") {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        text = "What-If Sandbox",
                        style = MaterialTheme.typography.displayLarge,
                        color = SandboxOn,
                    )
                    Text(
                        text = "Dry-run · cascade not committed",
                        style = MaterialTheme.typography.labelMedium,
                        color = SandboxMuted,
                    )
                }
            }
            item(key = "impact") {
                ImpactBanner(report = result.impactReport)
            }
            items(tasks, key = { it.id }) { task ->
                val isHypo = task.id in result.hypotheticalTaskIds ||
                    SimulationEngine.HYPOTHETICAL_TAG in task.tags
                SimulatedTaskRow(
                    task = task,
                    highlighted = isHypo,
                    onIntent = { /* sandbox is read-only for complete */ },
                )
            }
        }
    }
}

@Composable
private fun ImpactBanner(report: SimulationImpactReport) {
    val warning = report.parkedTaskDelta > 0 || report.hasDisruption
    Card(
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(
            containerColor = if (warning) Color(0xFF7C2D12) else SandboxSurface,
        ),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                text = if (warning) "Cascade impact" else "Clean injection",
                style = MaterialTheme.typography.titleLarge,
                color = if (warning) WarningAmber else SandboxOn,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = report.summaryLine,
                style = MaterialTheme.typography.bodyLarge,
                color = SandboxOn,
            )
            if (report.highLoadStreakDelta > 0) {
                Text(
                    text = "High-load streak +${report.highLoadStreakDelta}",
                    style = MaterialTheme.typography.labelMedium,
                    color = WarningAmber,
                )
            }
        }
    }
}

@Composable
private fun SimulatedTaskRow(
    task: LifeTask,
    highlighted: Boolean,
    onIntent: (LookAfterIntent) -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .then(
                if (highlighted) {
                    Modifier.background(Color.Transparent)
                } else {
                    Modifier
                },
            ),
    ) {
        Card(
            shape = RoundedCornerShape(16.dp),
            border = if (highlighted) BorderStroke(2.dp, HypoBorder) else null,
            colors = CardDefaults.cardColors(containerColor = SandboxSurface),
            modifier = Modifier.fillMaxWidth(),
        ) {
            // Reuse timeline card chrome inside sandbox colors via nested surface.
            Column(Modifier.padding(2.dp)) {
                if (highlighted) {
                    Text(
                        text = "HYPOTHETICAL",
                        style = MaterialTheme.typography.labelMedium,
                        color = HypoBorder,
                        modifier = Modifier.padding(start = 14.dp, top = 8.dp),
                    )
                }
                TimelineTaskCard(task = task, onIntent = onIntent)
            }
        }
    }
}

@Composable
private fun ActionFooter(
    onDiscard: () -> Unit,
    onCommit: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(SandboxSurface)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        OutlinedButton(
            onClick = onDiscard,
            modifier = Modifier.weight(1f),
            colors = ButtonDefaults.outlinedButtonColors(contentColor = SandboxOn),
            border = BorderStroke(1.dp, SandboxMuted),
        ) {
            Text("Discard")
        }
        Button(
            onClick = onCommit,
            modifier = Modifier.weight(1f),
            colors = ButtonDefaults.buttonColors(
                containerColor = HypoBorder,
                contentColor = SandboxViolet,
            ),
        ) {
            Text("Commit Schedule")
        }
    }
}
