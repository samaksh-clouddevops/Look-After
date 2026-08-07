package com.lookafter.app

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.lookafter.app.adhd.BodyDoubleAmbientAudio
import com.lookafter.app.auth.AuthSessionStore
import com.lookafter.app.execution.SystemFocusController
import com.lookafter.app.health.HealthConnectRepository
import com.lookafter.app.notifications.LookAfterNotifier
import com.lookafter.app.widget.TodayWidgetUpdater
import com.lookafter.core.adhd.FocusSessionEngine
import com.lookafter.core.adhd.FocusSessionIntent
import com.lookafter.core.adhd.FocusSessionPhase
import com.lookafter.core.adhd.FocusSessionState
import com.lookafter.core.brain.BrainTick
import com.lookafter.core.brain.CoachService
import com.lookafter.core.brain.ExecutiveBrainEngine
import com.lookafter.core.calendar.CalendarEvent
import com.lookafter.core.calendar.CalendarEventsProvider
import com.lookafter.core.engine.LifeEngine
import com.lookafter.core.engine.LifeState
import com.lookafter.core.engine.LookAfterIntent
import com.lookafter.core.health.HealthSummary
import com.lookafter.core.inbox.InboxEngine
import com.lookafter.core.inbox.InboxIntent
import com.lookafter.core.inbox.InboxState
import com.lookafter.core.insights.InsightsEngine
import com.lookafter.core.insights.InsightsSnapshot
import com.lookafter.core.notifications.NotificationPolicy
import com.lookafter.core.onboarding.OnboardingEngine
import com.lookafter.core.onboarding.OnboardingIntent
import com.lookafter.core.onboarding.OnboardingState
import com.lookafter.core.planning.MultiDayPlanEngine
import com.lookafter.core.planning.PlanMutationApplier
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/** Lifecycle bridge: Compose -> LifeEngine + platform adapters + pluggable coach. */
class LookAfterViewModel(
    application: Application,
) : AndroidViewModel(application) {

    private val app = application as LookAfterApplication
    private val engine: LifeEngine = app.lifeEngine
    private val healthRepo: HealthConnectRepository = app.healthRepository
    private val calendar: CalendarEventsProvider = app.calendarProvider
    private val notifier: LookAfterNotifier = app.notifier
    private val coach: CoachService = app.coachService
    private val systemFocus = SystemFocusController(application)
    private val ambientAudio = BodyDoubleAmbientAudio(application)
    private val authStore: AuthSessionStore = app.authSessionStore

    private val _ambientEnabled = MutableStateFlow(true)
    val ambientEnabled: StateFlow<Boolean> = _ambientEnabled.asStateFlow()

    val auth = authStore.state

    val insights: StateFlow<InsightsSnapshot> = combine(state, health) { life, h ->
        InsightsEngine.compute(life, h)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), InsightsSnapshot.EMPTY)

    fun setAmbientEnabled(enabled: Boolean) {
        _ambientEnabled.value = enabled
        if (!enabled) ambientAudio.stop()
        else if (_focus.value.phase == FocusSessionPhase.RUNNING) {
            ambientAudio.start(emergency = _focus.value.emergencyMode)
        }
    }

    /** Deep-link destination requested by widget / notifications (e.g. "today", "brain", "focus"). */
    private val _pendingDeepLink = MutableStateFlow<String?>(null)
    val pendingDeepLink: StateFlow<String?> = _pendingDeepLink.asStateFlow()

    fun consumeDeepLink() {
        _pendingDeepLink.value = null
    }

    fun handleDeepLink(target: String?) {
        if (target.isNullOrBlank()) return
        _pendingDeepLink.value = target.lowercase()
    }

    val state: StateFlow<LifeState> = engine.state
    val health: StateFlow<HealthSummary> = healthRepo.summary
    val healthPermissionGranted: StateFlow<Boolean> = healthRepo.permissionGranted
    val healthUsingDemo: StateFlow<Boolean> = healthRepo.usingDemo
    val healthRequiredPermissions: Set<String> get() = healthRepo.requiredPermissions()

    private val _onboarding = MutableStateFlow(app.initialOnboarding)
    val onboarding: StateFlow<OnboardingState> = _onboarding.asStateFlow()

    private val _inbox = MutableStateFlow(InboxState())
    val inbox: StateFlow<InboxState> = _inbox.asStateFlow()

    private val _focus = MutableStateFlow(FocusSessionState())
    val focus: StateFlow<FocusSessionState> = _focus.asStateFlow()

    private val _coachTranscript = MutableStateFlow<List<Pair<Boolean, String>>>(emptyList())
    val coachTranscript: StateFlow<List<Pair<Boolean, String>>> = _coachTranscript.asStateFlow()

    private val _calendarEvents = MutableStateFlow<List<CalendarEvent>>(emptyList())
    val calendarEvents: StateFlow<List<CalendarEvent>> = _calendarEvents.asStateFlow()

    /** Set by MainActivity to launch the HC permission contract. */
    var requestHealthPermissions: ((Set<String>) -> Unit)? = null
    /** Set by MainActivity to request READ_CALENDAR. */
    var requestCalendarPermission: (() -> Unit)? = null
    /** Set by MainActivity to open exact-alarm settings (Android 12+). */
    var openExactAlarmSettings: (() -> Unit)? = null

    val canScheduleExactAlarms: Boolean
        get() = notifier.canScheduleExactAlarms()

    val brainTick: StateFlow<BrainTick> = combine(
        state,
        health,
        focus,
        _calendarEvents,
    ) { life, h, f, cal ->
        ExecutiveBrainEngine.tick(
            life = life,
            health = h,
            calendarEvents = cal.map { it.toWorldCalendarEvent() },
            isInFlowSession = f.phase == FocusSessionPhase.RUNNING,
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), BrainTick())

    init {
        viewModelScope.launch { refreshCalendarDay() }
        // Re-plan notifications whenever brain tick updates.
        viewModelScope.launch {
            brainTick.collect { tick ->
                val inFocus = focus.value.phase == FocusSessionPhase.RUNNING
                val plans = NotificationPolicy.plan(
                    life = engine.currentState,
                    world = tick.world,
                    inFocusSession = inFocus,
                )
                notifier.scheduleAll(plans)
            }
        }
        // Keep home-screen Glance widget in sync with hero / open count.
        viewModelScope.launch {
            brainTick
                .map { it.decision.heroTitle to it.world.openTaskCount }
                .distinctUntilChanged()
                .collect {
                    TodayWidgetUpdater.requestUpdate(getApplication())
                }
        }
    }

    fun dispatch(intent: LookAfterIntent) {
        viewModelScope.launch { engine.process(intent) }
    }

    fun setHealthPermission(granted: Boolean) {
        if (granted) {
            // Prefer the real SDK permission contract when MainActivity wired it.
            val perms = healthRepo.requiredPermissions()
            val launcher = requestHealthPermissions
            if (launcher != null && perms.isNotEmpty()) {
                healthRepo.preferDemoFallback = false
                launcher(perms)
                return
            }
        }
        healthRepo.preferDemoFallback = granted
        healthRepo.markPermission(granted)
        viewModelScope.launch { healthRepo.refresh() }
    }

    fun onHealthPermissionResult(granted: Boolean) {
        healthRepo.markPermission(granted)
        if (!granted) {
            // Keep Briefing usable with demo metrics when HC is denied/missing.
            healthRepo.preferDemoFallback = true
            healthRepo.markPermission(true)
        } else {
            healthRepo.preferDemoFallback = false
        }
        viewModelScope.launch { healthRepo.refresh() }
    }

    fun refreshHealth() {
        viewModelScope.launch { healthRepo.refresh() }
    }

    fun dispatchOnboarding(intent: OnboardingIntent) {
        _onboarding.value = OnboardingEngine.reduce(_onboarding.value, intent)
        app.persistOnboarding(_onboarding.value)
    }

    fun dispatchInbox(intent: InboxIntent) {
        val result = InboxEngine.reduce(_inbox.value, intent)
        _inbox.value = result.state
        result.spawnedTask?.let { dispatch(LookAfterIntent.AddTask(it)) }
    }

    fun dispatchFocus(intent: FocusSessionIntent) {
        val previous = _focus.value.phase
        val next = FocusSessionEngine.reduce(_focus.value, intent)
        _focus.value = next
        syncSystemFocus(previousPhase = previous, session = next)
        if (next.phase == FocusSessionPhase.COMPLETED) {
            notifier.postNow(
                com.lookafter.core.notifications.PlannedNotification(
                    id = "focus-complete",
                    kind = com.lookafter.core.notifications.NotificationKind.FOCUS_COMPLETE,
                    title = if (next.emergencyMode) "Emergency block complete" else "Focus complete",
                    body = next.taskTitle.ifBlank { "Session finished" },
                    fireAt = java.time.Instant.now(),
                ),
            )
        }
    }

    private fun syncSystemFocus(previousPhase: FocusSessionPhase, session: FocusSessionState) {
        when (session.phase) {
            FocusSessionPhase.RUNNING -> {
                systemFocus.applySessionFocus(emergency = session.emergencyMode)
                if (_ambientEnabled.value) {
                    ambientAudio.start(emergency = session.emergencyMode)
                }
            }
            FocusSessionPhase.PAUSED,
            FocusSessionPhase.COMPLETED,
            FocusSessionPhase.ABORTED,
            FocusSessionPhase.IDLE,
            -> {
                ambientAudio.stop()
                // Release DND only when leaving an active/paused session.
                if (previousPhase == FocusSessionPhase.RUNNING ||
                    previousPhase == FocusSessionPhase.PAUSED
                ) {
                    systemFocus.releaseFocus()
                }
            }
        }
    }

    override fun onCleared() {
        ambientAudio.release()
        super.onCleared()
    }

    fun sendCoachMessage(text: String) {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return
        _coachTranscript.value = _coachTranscript.value + (true to trimmed)
        viewModelScope.launch {
            val life = engine.currentState
            // Multi-day / mutation proposal path first.
            val multi = MultiDayPlanEngine.interpret(trimmed, life)
            if (multi.proposal.mutations.isNotEmpty()) {
                val applied = PlanMutationApplier.apply(multi.proposal, life)
                applied.intents.forEach { engine.process(it) }
                _coachTranscript.value =
                    _coachTranscript.value + (false to multi.conversationalReply)
                return@launch
            }
            // Single-day deterministic intents (strip / park fluid / someday).
            val simple = MultiDayPlanEngine.simpleIntents(trimmed, life)
            if (simple.intents.isNotEmpty()) {
                simple.intents.forEach { engine.process(it) }
                _coachTranscript.value = _coachTranscript.value + (false to simple.reply)
                return@launch
            }
            val reply = coach.reply(
                userMessage = trimmed,
                life = engine.currentState,
                health = healthRepo.summary.value,
            )
            val finalReply = reply.ifBlank { multi.conversationalReply }
            _coachTranscript.value = _coachTranscript.value + (false to finalReply)
        }
    }

    fun signInLocal(displayName: String, email: String = "") {
        authStore.signInLocal(displayName, email)
    }

    fun signOut() {
        authStore.signOutToAnonymous()
    }

    fun setSyncEnabled(enabled: Boolean) {
        authStore.setSyncEnabled(enabled)
        if (enabled) authStore.markSyncedNow()
    }

    fun startFocusForHero(emergency: Boolean = false) {
        val tick = brainTick.value
        dispatchFocus(
            FocusSessionIntent.Start(
                taskId = tick.decision.heroTaskId,
                taskTitle = tick.decision.heroTitle,
                plannedMinutes = if (emergency) 10 else 25,
                emergencyMode = emergency,
            ),
        )
    }

    fun refreshCalendarDay() {
        viewModelScope.launch {
            _calendarEvents.value = calendar.eventsForDay(
                LocalDate.now(),
                ZoneId.systemDefault(),
            )
        }
    }

    fun ensureCalendarPermission() {
        requestCalendarPermission?.invoke()
    }

    fun requestExactAlarms() {
        openExactAlarmSettings?.invoke()
            ?: notifier.exactAlarmSettingsIntent()?.let { intent ->
                runCatching {
                    getApplication<Application>().startActivity(intent)
                }
            }
    }
}
