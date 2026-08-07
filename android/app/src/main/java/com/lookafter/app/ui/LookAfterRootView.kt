package com.lookafter.app.ui

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.lookafter.app.LookAfterViewModel
import com.lookafter.app.ui.brain.BrainScreen
import com.lookafter.app.ui.briefing.BriefingScreen
import com.lookafter.app.ui.components.LookAfterBottomNav
import com.lookafter.app.ui.navigation.AppDestination
import com.lookafter.app.ui.review.WeeklyReviewScreen
import com.lookafter.app.ui.simulation.SimulationScreen
import com.lookafter.app.ui.timeline.TodayTimelineScreen
import com.lookafter.app.ui.you.YouScreen
import com.lookafter.core.engine.LookAfterIntent
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.TaskExpirationPolicy
import com.lookafter.core.models.TaskStatus
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

/** App root — iOS shell parity: Briefing | Today | Capture | Brain | You */
@Composable
fun LookAfterRootView(
    viewModel: LookAfterViewModel,
    restoredFromDisk: Boolean = false,
    hydrationComplete: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    var destination by rememberSaveable { mutableStateOf(AppDestination.TODAY.name) }
    val current = AppDestination.entries.firstOrNull { it.name == destination } ?: AppDestination.TODAY
    var simulationOpen by remember { mutableStateOf(false) }
    var reviewOpen by remember { mutableStateOf(false) }
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
        bottomBar = {
            LookAfterBottomNav(
                current = if (reviewOpen) AppDestination.YOU else current,
                onSelect = { dest ->
                    reviewOpen = false
                    destination = dest.name
                },
                onCapture = {
                    viewModel.dispatch(
                        LookAfterIntent.AddTask(
                            LifeTask(
                                id = "cap-" + UUID.randomUUID(),
                                title = "Captured thought",
                                durationMinutes = 15,
                                constraintType = ConstraintType.FLUID,
                                status = TaskStatus.PENDING,
                                expirationPolicy = TaskExpirationPolicy.EndOfDay,
                                scheduledDate = state.currentDay ?: LocalDate.now(),
                                tags = listOf("capture"),
                            ),
                        ),
                    )
                    destination = AppDestination.TODAY.name
                    reviewOpen = false
                },
            )
        },
    ) { padding ->
        val contentModifier = Modifier.padding(padding).fillMaxSize()
        when {
            reviewOpen -> WeeklyReviewScreen(state = state, modifier = contentModifier)
            current == AppDestination.BRIEFING -> BriefingScreen(state = state, modifier = contentModifier)
            current == AppDestination.TODAY -> TodayTimelineScreen(
                state = state,
                onIntent = viewModel::dispatch,
                restoredFromDisk = restoredFromDisk,
                hydrationComplete = hydrationComplete,
                modifier = contentModifier,
            )
            current == AppDestination.BRAIN -> BrainScreen(state = state, modifier = contentModifier)
            current == AppDestination.YOU -> YouScreen(
                state = state,
                onOpenReview = { reviewOpen = true },
                onOpenSimulation = {
                    hypotheticals = listOf(dummyHypotheticalMeeting(state.currentDay))
                    simulationOpen = true
                },
                modifier = contentModifier,
            )
        }
    }
}

private fun dummyHypotheticalMeeting(currentDay: LocalDate?): LifeTask {
    val zone = ZoneId.systemDefault()
    val day = currentDay ?: LocalDate.now(zone)
    val start = day.atTime(11, 0).atZone(zone).toInstant()
    val end = day.atTime(13, 0).atZone(zone).toInstant()
    return LifeTask(
        id = "hypo-" + UUID.randomUUID(),
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
