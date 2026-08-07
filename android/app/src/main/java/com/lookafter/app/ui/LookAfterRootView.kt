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
import com.lookafter.app.ui.adhd.FocusSessionOverlay
import com.lookafter.app.ui.brain.BrainScreen
import com.lookafter.app.ui.briefing.BriefingScreen
import com.lookafter.app.ui.capture.CaptureSheet
import com.lookafter.app.ui.components.LookAfterBottomNav
import com.lookafter.app.ui.health.HealthScreen
import com.lookafter.app.ui.inbox.InboxScreen
import com.lookafter.app.ui.medication.MedicationScreen
import com.lookafter.app.ui.navigation.AppDestination
import com.lookafter.app.ui.onboarding.OnboardingScreen
import com.lookafter.app.ui.review.WeeklyReviewScreen
import com.lookafter.app.ui.simulation.SimulationScreen
import com.lookafter.app.ui.timeline.TodayTimelineScreen
import com.lookafter.app.ui.you.YouScreen
import com.lookafter.core.adhd.FocusSessionPhase
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.TaskExpirationPolicy
import com.lookafter.core.models.TaskStatus
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

@Composable
fun LookAfterRootView(
    viewModel: LookAfterViewModel,
    restoredFromDisk: Boolean = false,
    hydrationComplete: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val health by viewModel.health.collectAsStateWithLifecycle()
    val healthGranted by viewModel.healthPermissionGranted.collectAsStateWithLifecycle()
    val onboarding by viewModel.onboarding.collectAsStateWithLifecycle()
    val inbox by viewModel.inbox.collectAsStateWithLifecycle()
    val focus by viewModel.focus.collectAsStateWithLifecycle()
    val brainTick by viewModel.brainTick.collectAsStateWithLifecycle()
    val coach by viewModel.coachTranscript.collectAsStateWithLifecycle()
    val calendarEvents by viewModel.calendarEvents.collectAsStateWithLifecycle()

    var destination by rememberSaveable { mutableStateOf(AppDestination.TODAY.name) }
    val current = AppDestination.entries.firstOrNull { it.name == destination } ?: AppDestination.TODAY
    var simulationOpen by remember { mutableStateOf(false) }
    var reviewOpen by remember { mutableStateOf(false) }
    var medicationOpen by remember { mutableStateOf(false) }
    var healthOpen by remember { mutableStateOf(false) }
    var inboxOpen by remember { mutableStateOf(false) }
    var captureOpen by remember { mutableStateOf(false) }
    var focusOpen by remember { mutableStateOf(false) }
    var hypotheticals by remember { mutableStateOf<List<LifeTask>>(emptyList()) }

    if (!onboarding.completed) {
        OnboardingScreen(
            state = onboarding,
            onIntent = viewModel::dispatchOnboarding,
            modifier = modifier.fillMaxSize(),
        )
        return
    }

    if (focusOpen && focus.phase != FocusSessionPhase.IDLE) {
        FocusSessionOverlay(
            session = focus,
            onIntent = viewModel::dispatchFocus,
            onClose = { focusOpen = false },
            modifier = modifier.fillMaxSize(),
        )
        return
    }

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
                current = when {
                    reviewOpen || medicationOpen || healthOpen || inboxOpen -> AppDestination.YOU
                    else -> current
                },
                onSelect = { dest ->
                    reviewOpen = false; medicationOpen = false; healthOpen = false; inboxOpen = false
                    destination = dest.name
                },
                onCapture = { captureOpen = true },
            )
        },
    ) { padding ->
        if (captureOpen) {
            CaptureSheet(
                currentDay = state.currentDay,
                onIntent = { intent ->
                    viewModel.dispatch(intent)
                    destination = AppDestination.TODAY.name
                    reviewOpen = false; medicationOpen = false; healthOpen = false; inboxOpen = false
                },
                onDismiss = { captureOpen = false },
            )
        }
        val contentModifier = Modifier.padding(padding).fillMaxSize()
        when {
            medicationOpen -> MedicationScreen(state = state, onIntent = viewModel::dispatch, onBack = { medicationOpen = false }, modifier = contentModifier)
            healthOpen -> HealthScreen(summary = health, permissionGranted = healthGranted, onPermissionChange = viewModel::setHealthPermission, onRefresh = viewModel::refreshHealth, onBack = { healthOpen = false }, modifier = contentModifier)
            inboxOpen -> InboxScreen(state = inbox, onIntent = viewModel::dispatchInbox, onBack = { inboxOpen = false }, modifier = contentModifier)
            reviewOpen -> WeeklyReviewScreen(state = state, modifier = contentModifier)
            current == AppDestination.BRIEFING -> BriefingScreen(state = state, health = health, modifier = contentModifier)
            current == AppDestination.TODAY -> TodayTimelineScreen(
                state = state,
                onIntent = viewModel::dispatch,
                restoredFromDisk = restoredFromDisk,
                hydrationComplete = hydrationComplete,
                heroTitle = brainTick.decision.heroTitle,
                heroReason = brainTick.decision.reason,
                onStartFocus = {
                    viewModel.startFocusForHero()
                    focusOpen = true
                },
                modifier = contentModifier,
            )
            current == AppDestination.BRAIN -> BrainScreen(
                tick = brainTick,
                coachTranscript = coach,
                onSendCoach = viewModel::sendCoachMessage,
                onStartFocus = {
                    viewModel.startFocusForHero()
                    focusOpen = true
                },
                modifier = contentModifier,
            )
            current == AppDestination.YOU -> YouScreen(
                state = state,
                health = health,
                onOpenReview = { medicationOpen = false; healthOpen = false; inboxOpen = false; reviewOpen = true },
                onOpenSimulation = {
                    medicationOpen = false; healthOpen = false; inboxOpen = false
                    hypotheticals = listOf(dummyHypotheticalMeeting(state.currentDay))
                    simulationOpen = true
                },
                onOpenMedication = { reviewOpen = false; healthOpen = false; inboxOpen = false; medicationOpen = true },
                onOpenHealth = { reviewOpen = false; medicationOpen = false; inboxOpen = false; healthOpen = true },
                onOpenInbox = { reviewOpen = false; medicationOpen = false; healthOpen = false; inboxOpen = true },
                onConnectCalendar = { viewModel.ensureCalendarPermission() },
                calendarEventCount = calendarEvents.size,
                canScheduleExactAlarms = viewModel.canScheduleExactAlarms,
                onRequestExactAlarms = { viewModel.requestExactAlarms() },
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
