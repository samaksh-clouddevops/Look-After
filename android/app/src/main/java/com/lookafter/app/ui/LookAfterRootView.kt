package com.lookafter.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.lookafter.app.LookAfterViewModel
import com.lookafter.core.engine.LifeState
import com.lookafter.core.engine.LookAfterIntent
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.TaskStatus
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

/**
 * Phase-3/4 proof UI — active task counts, midnight-sweep, restore status.
 * Full timeline is intentionally out of scope.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LookAfterRootView(
    viewModel: LookAfterViewModel,
    restoredFromDisk: Boolean = false,
    hydrationComplete: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()

    Scaffold(
        modifier = modifier.fillMaxSize(),
        topBar = {
            TopAppBar(title = { Text("Look After — UDF proof") })
        },
    ) { padding ->
        ProofContent(
            state = state,
            restoredFromDisk = restoredFromDisk,
            hydrationComplete = hydrationComplete,
            onMidnightSweep = {
                val zone = ZoneOffset.systemDefault()
                val today = LocalDate.now(zone)
                viewModel.dispatch(
                    LookAfterIntent.TriggerMidnightSweep(
                        previousDay = today.minusDays(1),
                        nextDay = today,
                        now = Instant.now(),
                        zone = zone,
                    ),
                )
            },
            modifier = Modifier
                .padding(padding)
                .padding(16.dp)
                .fillMaxSize(),
        )
    }
}

@Composable
private fun ProofContent(
    state: LifeState,
    restoredFromDisk: Boolean,
    hydrationComplete: Boolean,
    onMidnightSweep: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val active = state.activeTasks
    val pending = active.count { it.status.isActive }
    val expired = active.count { it.status == TaskStatus.EXPIRED }
    val parked = state.parkedQueue.size
    val restoreLabel = when {
        !hydrationComplete -> "Persistence: hydrating…"
        restoredFromDisk -> "Persistence: restored from disk ✓"
        else -> "Persistence: fresh seed (first launch)"
    }

    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Active tasks: ${active.size}", style = MaterialTheme.typography.headlineSmall)
        Text(restoreLabel, style = MaterialTheme.typography.bodyMedium)
        Text("Pending / in-progress: $pending")
        Text("Expired in active pool: $expired")
        Text("Parked queue: $parked")
        Text("Action logs: ${state.actionLogs.size}")
        Text("Current day: ${state.currentDay ?: "—"}")

        Button(
            onClick = onMidnightSweep,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text("Trigger midnight sweep")
        }

        Spacer(Modifier.height(8.dp))
        Text("Tasks", style = MaterialTheme.typography.titleMedium)
        LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(active, key = { it.id }) { task ->
                TaskRow(task)
            }
        }
    }
}

@Composable
private fun TaskRow(task: LifeTask) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp)) {
            Text(task.title, style = MaterialTheme.typography.titleSmall)
            Text("status=${task.status}  exp=${task.expirationPolicy}")
            Text("id=${task.id}", style = MaterialTheme.typography.bodySmall)
        }
    }
}
