package com.lookafter.app.ui.timeline

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.lookafter.core.engine.LifeState
import com.lookafter.core.engine.LookAfterIntent
import com.lookafter.core.models.TaskStatus
import java.time.LocalDate

/**
 * Primary Today surface — Golden Ratio header + timeline of active tasks.
 */
@Composable
fun TodayTimelineScreen(
    state: LifeState,
    onIntent: (LookAfterIntent) -> Unit,
    modifier: Modifier = Modifier,
    restoredFromDisk: Boolean = false,
    hydrationComplete: Boolean = true,
) {
    // Prefer still-actionable work; completed stay visible for the session.
    val tasks = state.activeTasks
        .sortedWith(
            compareBy<com.lookafter.core.models.LifeTask> {
                when (it.status) {
                    TaskStatus.COMPLETED, TaskStatus.EXPIRED, TaskStatus.SUPERSEDED -> 1
                    else -> 0
                }
            }.thenBy { it.scheduledStart ?: java.time.Instant.MAX },
        )

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 20.dp, vertical = 24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item(key = "header") {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 8.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(
                    text = "Today's Execution",
                    style = MaterialTheme.typography.displayLarge,
                    color = MaterialTheme.colorScheme.onBackground,
                )
                Text(
                    text = subtitle(state, restoredFromDisk, hydrationComplete),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        if (tasks.isEmpty()) {
            item(key = "empty") {
                EquilibriumEmptyState(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 72.dp),
                )
            }
        } else {
            items(tasks, key = { it.id }) { task ->
                TimelineTaskCard(task = task, onIntent = onIntent)
            }
        }
    }
}

@Composable
private fun EquilibriumEmptyState(modifier: Modifier = Modifier) {
    Box(
        modifier = modifier,
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                text = "Equilibrium Achieved",
                style = MaterialTheme.typography.titleLarge,
                color = MaterialTheme.colorScheme.onBackground,
                textAlign = TextAlign.Center,
            )
            Text(
                text = "No active work on the board. Protect the quiet.",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
    }
}

private fun subtitle(
    state: LifeState,
    restoredFromDisk: Boolean,
    hydrationComplete: Boolean,
): String {
    val day = state.currentDay?.toString() ?: LocalDate.now().toString()
    val pending = state.activeTasks.count { it.status.isActive }
    val persistence = when {
        !hydrationComplete -> "loading…"
        restoredFromDisk -> "restored"
        else -> "fresh"
    }
    return "$day · $pending open · $persistence"
}
