package com.lookafter.app.ui

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Science
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.lookafter.app.LookAfterViewModel
import com.lookafter.app.ui.navigation.AppDestination
import com.lookafter.app.ui.review.WeeklyReviewScreen
import com.lookafter.app.ui.simulation.SimulationScreen
import com.lookafter.app.ui.timeline.TodayTimelineScreen
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.TaskExpirationPolicy
import com.lookafter.core.models.TaskStatus
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

/**
 * App root — bottom nav Today / Review, plus What-If simulation overlay.
 */
@Composable
fun LookAfterRootView(
    viewModel: LookAfterViewModel,
    restoredFromDisk: Boolean = false,
    hydrationComplete: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    var destination by rememberSaveable { mutableStateOf(AppDestination.TODAY.name) }
    val current = AppDestination.entries.firstOrNull { it.name == destination }
        ?: AppDestination.TODAY
    var simulationOpen by remember { mutableStateOf(false) }
    var hypotheticals by remember { mutableStateOf<List<LifeTask>>(emptyList()) }

    if (simulationOpen && hypotheticals.isNotEmpty()) {
        SimulationScreen(
            baselineState = state,
            hypotheticalTasks = hypotheticals,
            onCommit = { intent ->
                viewModel.dispatch(intent)
                simulationOpen = false
                hypotheticals = emptyList()
            },
            onDiscard = {
                simulationOpen = false
                hypotheticals = emptyList()
            },
            modifier = modifier.fillMaxSize(),
        )
        return
    }

    Scaffold(
        modifier = modifier.fillMaxSize(),
        floatingActionButton = {
            if (current == AppDestination.TODAY) {
                FloatingActionButton(
                    onClick = {
                        hypotheticals = listOf(dummyHypotheticalMeeting(state.currentDay))
                        simulationOpen = true
                    },
                ) {
                    Icon(
                        imageVector = Icons.Outlined.Science,
                        contentDescription = "Simulate what-if",
                    )
                }
            }
        },
        bottomBar = {
            NavigationBar {
                AppDestination.entries.forEach { dest ->
                    NavigationBarItem(
                        selected = dest == current,
                        onClick = { destination = dest.name },
                        icon = {
                            Icon(
                                imageVector = dest.icon,
                                contentDescription = dest.label,
                            )
                        },
                        label = { Text(dest.label) },
                    )
                }
            }
        },
    ) { padding ->
        val contentModifier = Modifier
            .padding(padding)
            .fillMaxSize()

        when (current) {
            AppDestination.TODAY -> TodayTimelineScreen(
                state = state,
                onIntent = viewModel::dispatch,
                restoredFromDisk = restoredFromDisk,
                hydrationComplete = hydrationComplete,
                modifier = contentModifier,
            )
            AppDestination.REVIEW -> WeeklyReviewScreen(
                state = state,
                modifier = contentModifier,
            )
        }
    }
}

/** Phase-9 demo injector: 2h anchored meeting into the middle of today. */
private fun dummyHypotheticalMeeting(currentDay: LocalDate?): LifeTask {
    val zone = ZoneId.systemDefault()
    val day = currentDay ?: LocalDate.now(zone)
    val start = day.atTime(11, 0).atZone(zone).toInstant()
    val end = day.atTime(13, 0).atZone(zone).toInstant()
    return LifeTask(
        id = "hypo-${UUID.randomUUID()}",
        title = "Hypothetical Meeting",
        durationMinutes = 120,
        constraintType = ConstraintType.ANCHORED,
        status = TaskStatus.PENDING,
        expirationPolicy = TaskExpirationPolicy.EndOfDay,
        scheduledDate = day,
        scheduledStart = start,
        scheduledEnd = end,
        tags = listOf("hypothetical"),
    )
}
