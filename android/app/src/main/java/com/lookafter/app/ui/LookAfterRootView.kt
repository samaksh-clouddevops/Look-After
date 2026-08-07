package com.lookafter.app.ui

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import com.lookafter.app.ui.components.LookAfterBottomNav
import com.lookafter.app.ui.health.HealthScreen
import com.lookafter.app.ui.inbox.InboxScreen
import com.lookafter.app.ui.insights.InsightsScreen
import com.lookafter.app.ui.medication.MedicationScreen
import com.lookafter.app.ui.motion.CalmAnimatedContent
import com.lookafter.app.ui.navigation.AppDestination
import com.lookafter.app.ui.onboarding.OnboardingScreen
import com.lookafter.app.ui.review.WeeklyReviewScreen
import com.lookafter.app.ui.simulation.SimulationScreen
import com.lookafter.app.ui.tasks.TaskEditorSheet
import com.lookafter.app.ui.timeline.TodayTimelineScreen
import com.lookafter.app.ui.you.YouScreen
import com.lookafter.app.widget.LookAfterDeepLink
import com.lookafter.core.adhd.FocusSessionPhase
import com.lookafter.core.engine.LookAfterIntent
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
    val deepLink by viewModel.pendingDeepLink.collectAsStateWithLifecycle()
    val ambientEnabled by viewModel.ambientEnabled.collectAsStateWithLifecycle()
    val insights by viewModel.insights.collectAsStateWithLifecycle()
    val auth by viewModel.auth.collectAsStateWithLifecycle()
    val cameraBodyDouble by viewModel.cameraBodyDoubleEnabled.collectAsStateWithLifecycle()
    val syncMessage by viewModel.lastSyncMessage.collectAsStateWithLifecycle()

    var destination by rememberSaveable { mutableStateOf(AppDestination.TODAY.name) }
    val current = AppDestination.entries.firstOrNull { it.name == destination } ?: AppDestination.TODAY
    var simulationOpen by remember { mutableStateOf(false) }
    var reviewOpen by remember { mutableStateOf(false) }
    var medicationOpen by remember { mutableStateOf(false) }
    var healthOpen by remember { mutableStateOf(false) }
    var inboxOpen by remember { mutableStateOf(false) }
    var insightsOpen by remember { mutableStateOf(false) }
    var captureOpen by remember { mutableStateOf(false) }
    var focusOpen by remember { mutableStateOf(false) }
    var editingTask by remember { mutableStateOf<LifeTask?>(null) }
    var hypotheticals by remember { mutableStateOf<List<LifeTask>>(emptyList()) }

    LaunchedEffect(deepLink) {
        val target = deepLink ?: return@LaunchedEffect
        when (target) {
            LookAfterDeepLink.TARGET_TODAY -> {
                destination = AppDestination.TODAY.name
                reviewOpen = false; medicationOpen = false; healthOpen = false; inboxOpen = false
            }
            LookAfterDeepLink.TARGET_BRAIN -> {
                destination = AppDestination.BRAIN.name
                reviewOpen = false; medicationOpen = false; healthOpen = false; inboxOpen = false
            }
            LookAfterDeepLink.TARGET_FOCUS -> {
                destination = AppDestination.TODAY.name
                viewModel.startFocusForHero()
                focusOpen = true
            }
        }
        viewModel.consumeDeepLink()
    }

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
            cameraBodyDouble = cameraBodyDouble,
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
                    reviewOpen || medicationOpen || healthOpen || inboxOpen || insightsOpen ->
                        AppDestination.YOU
                    else -> current
                },
                onSelect = { dest ->
                    reviewOpen = false
                    medicationOpen = false
                    healthOpen = false
                    inboxOpen = false
                    insightsOpen = false
                    destination = dest.name
                },
                onCapture = { captureOpen = true },
            )
        },
    ) { padding ->
        if (captureOpen || editingTask != null) {
            TaskEditorSheet(
                currentDay = state.currentDay,
                existing = editingTask,
                onIntent = { intent ->
                    viewModel.dispatch(intent)
                    destination = AppDestination.TODAY.name
                    reviewOpen = false; medicationOpen = false; healthOpen = false; inboxOpen = false
                },
                onDismiss = {
                    captureOpen = false
                    editingTask = null
                },
                onDelete = { task ->
                    viewModel.dispatch(LookAfterIntent.DeleteTask(task.id))
                },
            )
        }
        val contentModifier = Modifier.padding(padding).fillMaxSize()
        // Calm cross-fade when switching tabs / sub-surfaces (iOS-like ease).
        val surfaceKey = when {
            medicationOpen -> "med"
            healthOpen -> "health"
            inboxOpen -> "inbox"
            insightsOpen -> "insights"
            reviewOpen -> "review"
            else -> current.name
        }
        CalmAnimatedContent(targetState = surfaceKey, modifier = contentModifier) {
            when {
                medicationOpen -> MedicationScreen(
                    state = state,
                    onIntent = viewModel::dispatch,
                    onBack = { medicationOpen = false },
                    modifier = Modifier.fillMaxSize(),
                )
                healthOpen -> HealthScreen(
                    summary = health,
                    permissionGranted = healthGranted,
                    onPermissionChange = viewModel::setHealthPermission,
                    onRefresh = viewModel::refreshHealth,
                    onBack = { healthOpen = false },
                    modifier = Modifier.fillMaxSize(),
                )
                inboxOpen -> InboxScreen(
                    state = inbox,
                    onIntent = viewModel::dispatchInbox,
                    onBack = { inboxOpen = false },
                    modifier = Modifier.fillMaxSize(),
                )
                insightsOpen -> InsightsScreen(
                    snapshot = insights,
                    onBack = { insightsOpen = false },
                    modifier = Modifier.fillMaxSize(),
                )
                reviewOpen -> WeeklyReviewScreen(state = state, modifier = Modifier.fillMaxSize())
                current == AppDestination.BRIEFING -> BriefingScreen(
                    state = state,
                    health = health,
                    modifier = Modifier.fillMaxSize(),
                )
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
                    onOpenTask = { task -> editingTask = task },
                    onCreateTask = {
                        editingTask = null
                        captureOpen = true
                    },
                    modifier = Modifier.fillMaxSize(),
                )
                current == AppDestination.BRAIN -> BrainScreen(
                    tick = brainTick,
                    coachTranscript = coach,
                    onSendCoach = viewModel::sendCoachMessage,
                    onStartFocus = {
                        viewModel.startFocusForHero(emergency = false)
                        focusOpen = true
                    },
                    onEmergencyFocus = {
                        viewModel.startFocusForHero(emergency = true)
                        focusOpen = true
                    },
                    modifier = Modifier.fillMaxSize(),
                )
                current == AppDestination.YOU -> YouScreen(
                    state = state,
                    health = health,
                    insights = insights,
                    auth = auth,
                    ambientEnabled = ambientEnabled,
                    onAmbientChange = viewModel::setAmbientEnabled,
                    cameraBodyDouble = cameraBodyDouble,
                    onCameraBodyDoubleChange = viewModel::setCameraBodyDoubleEnabled,
                    firebaseAvailable = viewModel.firebaseAuthAvailable,
                    syncMessage = syncMessage,
                    onOpenReview = {
                        medicationOpen = false; healthOpen = false; inboxOpen = false
                        insightsOpen = false; reviewOpen = true
                    },
                    onOpenSimulation = {
                        medicationOpen = false; healthOpen = false; inboxOpen = false
                        insightsOpen = false
                        hypotheticals = listOf(dummyHypotheticalMeeting(state.currentDay))
                        simulationOpen = true
                    },
                    onOpenMedication = {
                        reviewOpen = false; healthOpen = false; inboxOpen = false
                        insightsOpen = false; medicationOpen = true
                    },
                    onOpenHealth = {
                        reviewOpen = false; medicationOpen = false; inboxOpen = false
                        insightsOpen = false; healthOpen = true
                    },
                    onOpenInbox = {
                        reviewOpen = false; medicationOpen = false; healthOpen = false
                        insightsOpen = false; inboxOpen = true
                    },
                    onOpenInsights = {
                        reviewOpen = false; medicationOpen = false; healthOpen = false
                        inboxOpen = false; insightsOpen = true
                    },
                    onConnectCalendar = { viewModel.ensureCalendarPermission() },
                    calendarEventCount = calendarEvents.size,
                    canScheduleExactAlarms = viewModel.canScheduleExactAlarms,
                    onRequestExactAlarms = { viewModel.requestExactAlarms() },
                    onSignInLocal = { viewModel.signInLocal(it) },
                    onSignInFirebaseAnonymous = { viewModel.signInFirebaseAnonymous() },
                    onSignOut = { viewModel.signOut() },
                    onSyncChange = { viewModel.setSyncEnabled(it) },
                    onPushSync = { viewModel.pushSync() },
                    onPullSync = { viewModel.pullSync() },
                    modifier = Modifier.fillMaxSize(),
                )
            }
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
