package com.lookafter.app

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.lookafter.app.adhd.BodyDoubleAmbientAudio
import com.lookafter.app.auth.AuthSessionStore
import com.lookafter.app.auth.FirebaseAuthBridge
import com.lookafter.app.brain.CoachHistoryStore
import com.lookafter.app.brain.HttpLlmPlanService
import com.lookafter.app.brain.StreamingLlmClient
import com.lookafter.app.diagnostics.CrashReporting
import com.lookafter.app.execution.SystemFocusController
import com.lookafter.app.health.HealthConnectRepository
import com.lookafter.app.notifications.LookAfterNotifier
import com.lookafter.app.notifications.NotificationPreferencesStore
import com.lookafter.app.planning.PlanningConversationStore
import com.lookafter.app.sync.LifeStateSyncTransport
import com.lookafter.app.webrtc.WebRtcPeerController
import com.lookafter.app.widget.TodayWidgetUpdater
import com.lookafter.core.adhd.BodyDoubleRoomEngine
import com.lookafter.core.adhd.BodyDoubleRoomIntent
import com.lookafter.core.adhd.BodyDoubleRoomState
import com.lookafter.core.adhd.BodyDoubleSignalType
import com.lookafter.core.adhd.FocusSessionEngine
import com.lookafter.core.adhd.FocusSessionIntent
import com.lookafter.core.adhd.FocusSessionPhase
import com.lookafter.core.adhd.FocusSessionState
import com.lookafter.core.adhd.IceServerConfig
import com.lookafter.core.brain.BrainContextPack
import com.lookafter.core.brain.BrainTick
import com.lookafter.core.brain.CoachHistoryEngine
import com.lookafter.core.brain.CoachHistoryIntent
import com.lookafter.core.brain.CoachHistoryState
import com.lookafter.core.brain.CoachService
import com.lookafter.core.brain.ExecutiveBrainEngine
import com.lookafter.core.calendar.CalendarEvent
import com.lookafter.core.calendar.CalendarEventsProvider
import com.lookafter.core.capacity.ExecutiveCapacity
import com.lookafter.core.capacity.ExecutiveCapacityEngine
import com.lookafter.core.engine.LifeEngine
import com.lookafter.core.engine.LifeState
import com.lookafter.core.engine.LookAfterIntent
import com.lookafter.core.health.HealthSummary
import com.lookafter.core.inbox.InboxEngine
import com.lookafter.core.inbox.InboxIntent
import com.lookafter.core.inbox.InboxState
import com.lookafter.core.insights.InsightsEngine
import com.lookafter.core.insights.InsightsSnapshot
import com.lookafter.core.notifications.NotificationPreferences
import com.lookafter.core.notifications.NotificationPolicy
import com.lookafter.core.onboarding.OnboardingEngine
import com.lookafter.core.onboarding.OnboardingIntent
import com.lookafter.core.onboarding.OnboardingState
import com.lookafter.core.planning.MultiDayPlanEngine
import com.lookafter.core.planning.PlanMutationApplier
import com.lookafter.core.planning.PlanMutationDiff
import com.lookafter.core.planning.PlanningConversationEngine
import com.lookafter.core.planning.PlanningConversationIntent
import com.lookafter.core.planning.PlanningConversationState
import com.lookafter.core.planning.PlanningHorizons
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.Job
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
    private val notificationPrefsStore: NotificationPreferencesStore = app.notificationPrefs
    private val planningStore: PlanningConversationStore = app.planningConversationStore
    private val coachHistoryStore: CoachHistoryStore = app.coachHistoryStore
    private val coach: CoachService = app.coachService
    private val planService: HttpLlmPlanService = app.planService
    private val streamingLlm: StreamingLlmClient = app.streamingLlm
    private val iceConfig: IceServerConfig = app.iceConfig
    private val syncTransport: LifeStateSyncTransport = app.syncTransport
    private val systemFocus = SystemFocusController(application)
    private val ambientAudio = BodyDoubleAmbientAudio(application)
    private val authStore: AuthSessionStore = app.authSessionStore
    private var streamJob: Job? = null
    private var webRtc: WebRtcPeerController? = null
    private var lastAutoHeroKey: String? = null

    val notificationPreferences: StateFlow<NotificationPreferences> = notificationPrefsStore.state

    private val _coachHistory = MutableStateFlow(app.coachHistoryStore.load())
    val coachHistory: StateFlow<CoachHistoryState> = _coachHistory.asStateFlow()

    private val _ambientEnabled = MutableStateFlow(true)
    val ambientEnabled: StateFlow<Boolean> = _ambientEnabled.asStateFlow()

    val hapticsEnabled: Boolean
        get() = notificationPreferences.value.hapticsEnabled

    fun updateNotificationPreferences(prefs: NotificationPreferences) {
        notificationPrefsStore.set(prefs)
    }

    fun updateNotificationPreferences(transform: (NotificationPreferences) -> NotificationPreferences) {
        notificationPrefsStore.update(transform)
    }

    private fun persistPlanning(next: PlanningConversationState) {
        _planning.value = next
        planningStore.save(next)
    }

    private fun persistCoachHistory(next: CoachHistoryState) {
        _coachHistory.value = next
        coachHistoryStore.save(next)
    }

    private fun recordCoachHistory(intent: CoachHistoryIntent) {
        persistCoachHistory(CoachHistoryEngine.reduce(_coachHistory.value, intent))
    }

    fun pinCoachHistory(id: String, pinned: Boolean) {
        recordCoachHistory(CoachHistoryIntent.Pin(id, pinned))
    }

    fun removeCoachHistory(id: String) {
        recordCoachHistory(CoachHistoryIntent.Remove(id))
    }

    fun clearUnpinnedCoachHistory() {
        recordCoachHistory(CoachHistoryIntent.ClearUnpinned)
    }

    /** Pin current brain hero decision as "why this hero". */
    fun pinCurrentHeroDecision() {
        val tick = brainTick.value
        val entry = CoachHistoryEngine.fromHeroDecision(
            decision = tick.decision,
            world = tick.world,
            now = Instant.now(),
        ).copy(pinned = true)
        recordCoachHistory(CoachHistoryIntent.Record(entry))
        _lastSyncMessage.value = "Pinned hero · ${entry.title}"
    }

    private val _cameraBodyDouble = MutableStateFlow(false)
    val cameraBodyDoubleEnabled: StateFlow<Boolean> = _cameraBodyDouble.asStateFlow()

    private val _lastSyncMessage = MutableStateFlow<String?>(null)
    val lastSyncMessage: StateFlow<String?> = _lastSyncMessage.asStateFlow()

    private val _streamingCoach = MutableStateFlow(false)
    val streamingCoach: StateFlow<Boolean> = _streamingCoach.asStateFlow()

    private val _streamingPlan = MutableStateFlow(false)
    val streamingPlan: StateFlow<Boolean> = _streamingPlan.asStateFlow()

    private val _planDraftPreview = MutableStateFlow<String?>(null)
    val planDraftPreview: StateFlow<String?> = _planDraftPreview.asStateFlow()

    private val _webRtcState =
        MutableStateFlow(WebRtcPeerController.ConnectionState.NEW)
    val webRtcConnectionState: StateFlow<WebRtcPeerController.ConnectionState> =
        _webRtcState.asStateFlow()

    private var planStreamJob: Job? = null

    val auth = authStore.state
    val firebaseAuthAvailable: Boolean get() = FirebaseAuthBridge.isAvailable()
    val llmPlanConfigured: Boolean get() = planService.isConfigured
    val streamingLlmConfigured: Boolean get() = streamingLlm.isConfigured

    val insights: StateFlow<InsightsSnapshot> = combine(state, health) { life, h ->
        InsightsEngine.compute(life, h)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), InsightsSnapshot.EMPTY)

    fun setCameraBodyDoubleEnabled(enabled: Boolean) {
        _cameraBodyDouble.value = enabled
    }

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

    private val _planning = MutableStateFlow(app.planningConversationStore.load())
    val planning: StateFlow<PlanningConversationState> = _planning.asStateFlow()

    /** Back-compat transcript projection for Brain UI. */
    val coachTranscript: StateFlow<List<Pair<Boolean, String>>> =
        _planning.map { it.transcript }
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val planningHorizonDays: Int
        get() = _planning.value.horizonDays

    fun setPlanningHorizonDays(days: Int) {
        val bundle = PlanningConversationEngine.reduce(
            _planning.value,
            PlanningConversationIntent.SetHorizonDays(days),
        )
        persistPlanning(bundle.state)
    }

    private val _bodyDoubleRoom = MutableStateFlow(BodyDoubleRoomState())
    val bodyDoubleRoom: StateFlow<BodyDoubleRoomState> = _bodyDoubleRoom.asStateFlow()

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

    val executiveCapacity: StateFlow<ExecutiveCapacity> = combine(state, health, brainTick) { life, h, tick ->
        ExecutiveCapacityEngine.compute(life, h, tick.world)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), ExecutiveCapacity.EMPTY)

    init {
        viewModelScope.launch { refreshCalendarDay() }
        // Re-plan notifications whenever brain tick or prefs update.
        viewModelScope.launch {
            combine(brainTick, notificationPreferences, focus) { tick, prefs, f ->
                Triple(tick, prefs, f)
            }.collect { (tick, prefs, f) ->
                val inFocus = f.phase == FocusSessionPhase.RUNNING
                val plans = NotificationPolicy.plan(
                    life = engine.currentState,
                    world = tick.world,
                    inFocusSession = inFocus,
                    config = prefs.toPolicyConfig(),
                )
                notifier.scheduleAll(plans)
            }
        }
        // Soft-record hero decision when it changes (unpinned; user can pin).
        viewModelScope.launch {
            brainTick
                .map { it.decision.heroTaskId to it.decision.heroTitle }
                .distinctUntilChanged()
                .collect { (id, title) ->
                    val key = "${id.orEmpty()}|$title"
                    if (key == lastAutoHeroKey || title.isBlank() || title == "Nothing queued") {
                        return@collect
                    }
                    lastAutoHeroKey = key
                    val tick = brainTick.value
                    recordCoachHistory(
                        CoachHistoryIntent.Record(
                            CoachHistoryEngine.fromHeroDecision(
                                decision = tick.decision,
                                world = tick.world,
                                now = Instant.now(),
                            ),
                        ),
                    )
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
        if (next.phase == FocusSessionPhase.COMPLETED &&
            notificationPreferences.value.focusCompleteEnabled
        ) {
            val prefs = notificationPreferences.value
            val fireAt = java.time.Instant.now()
            if (!prefs.isInQuietHours(fireAt)) {
                notifier.postNow(
                    com.lookafter.core.notifications.PlannedNotification(
                        id = "focus-complete",
                        kind = com.lookafter.core.notifications.NotificationKind.FOCUS_COMPLETE,
                        title = if (next.emergencyMode) {
                            "Emergency block complete"
                        } else {
                            "Focus complete"
                        },
                        body = next.taskTitle.ifBlank { "Session finished" },
                        fireAt = fireAt,
                    ),
                )
            }
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
        streamJob?.cancel()
        planStreamJob?.cancel()
        webRtc?.close()
        ambientAudio.release()
        super.onCleared()
    }

    fun sendCoachMessage(text: String) {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return
        // Append user turn into multi-turn planning conversation.
        persistPlanning(
            PlanningConversationEngine.reduce(
                _planning.value,
                PlanningConversationIntent.UserMessage(trimmed),
            ).state,
        )
        viewModelScope.launch {
            val life = engine.currentState
            val healthSnap = healthRepo.summary.value
            val horizon = _planning.value.horizonDays.coerceIn(1, 14)
            val looksLikePlan = trimmed.length > 12 ||
                trimmed.contains("spread") ||
                trimmed.contains("plan") ||
                trimmed.contains("tomorrow") ||
                trimmed.contains("week") ||
                trimmed.contains("reschedule") ||
                trimmed.contains("morning") ||
                trimmed.contains("overwhelm") ||
                trimmed.contains("park fluid") ||
                trimmed.contains("horizon")
            if (looksLikePlan) {
                // Deterministic single-day intents still apply immediately (strip/park).
                val simple = MultiDayPlanEngine.simpleIntents(trimmed, life)
                if (simple.intents.isNotEmpty()) {
                    simple.intents.forEach { engine.process(it) }
                    persistPlanning(
                        PlanningConversationEngine.reduce(
                            _planning.value,
                            PlanningConversationIntent.CoachReply(simple.reply),
                        ).state,
                    )
                    return@launch
                }
                // Stream JSON plan (LLM) → parse → pending review; fail-soft offline.
                streamPlanProposal(trimmed, life, healthSnap, horizon)
                return@launch
            }
            // Streaming coach tokens when LLM is configured; else offline block reply.
            streamCoachReply(trimmed, life, healthSnap)
        }
    }

    private fun streamPlanProposal(
        message: String,
        life: LifeState,
        healthSnap: HealthSummary,
        horizon: Int,
    ) {
        planStreamJob?.cancel()
        planStreamJob = viewModelScope.launch {
            _streamingPlan.value = true
            _planDraftPreview.value = "Planning…"
            _lastSyncMessage.value = "Planning… streaming"
            var offered = false
            runCatching {
                planService.streamPlan(
                    message = message,
                    state = life,
                    health = healthSnap,
                    horizonDays = horizon,
                ).collect { event ->
                    when (event) {
                        is HttpLlmPlanService.PlanStreamEvent.Draft -> {
                            _planDraftPreview.value = event.preview.ifBlank {
                                "Planning… ${event.chars} chars"
                            }
                        }
                        is HttpLlmPlanService.PlanStreamEvent.Complete -> {
                            val planned = event.result
                            val proposal = planned.proposal.copy(
                                dayHorizon = planned.proposal.dayHorizon.coerceAtLeast(horizon),
                            )
                            val src = when (planned.source) {
                                HttpLlmPlanService.PlanResult.Source.LLM_STREAM -> "LLM stream"
                                HttpLlmPlanService.PlanResult.Source.LLM -> "LLM"
                                HttpLlmPlanService.PlanResult.Source.OFFLINE -> "offline"
                            }
                            if (proposal.mutations.isNotEmpty()) {
                                persistPlanning(
                                    PlanningConversationEngine.reduce(
                                        _planning.value,
                                        PlanningConversationIntent.OfferPlan(
                                            proposal = proposal,
                                            reply = planned.conversationalReply,
                                            sourceLabel = "$src · ${horizon}d",
                                        ),
                                    ).state,
                                )
                                _lastSyncMessage.value =
                                    "Plan ready · ${proposal.mutations.size} change(s) · review"
                                offered = true
                            } else {
                                persistPlanning(
                                    PlanningConversationEngine.reduce(
                                        _planning.value,
                                        PlanningConversationIntent.CoachReply(
                                            planned.conversationalReply.ifBlank {
                                                "No board changes proposed — try a clearer plan ask."
                                            },
                                        ),
                                    ).state,
                                )
                            }
                        }
                    }
                }
            }.onFailure {
                CrashReporting.recordNonFatal(it, "stream plan")
                // Offline fail-soft
                val (offlineProposal, offlineReply) = PlanningConversationEngine.offlineTurn(
                    message = message,
                    life = life,
                    horizonDays = horizon,
                )
                if (offlineProposal.mutations.isNotEmpty() && !offered) {
                    persistPlanning(
                        PlanningConversationEngine.reduce(
                            _planning.value,
                            PlanningConversationIntent.OfferPlan(
                                proposal = offlineProposal.copy(dayHorizon = horizon),
                                reply = offlineReply,
                                sourceLabel = "offline · ${horizon}d",
                            ),
                        ).state,
                    )
                    _lastSyncMessage.value =
                        "Plan ready · ${offlineProposal.mutations.size} change(s) · offline"
                } else if (!offered) {
                    appendCoach(offlineReply.ifBlank { "Plan stream failed — try again or use offline strip/park commands." })
                }
            }
            _streamingPlan.value = false
            _planDraftPreview.value = null
        }
    }

    private fun streamCoachReply(
        userMessage: String,
        life: LifeState,
        healthSnap: HealthSummary,
    ) {
        streamJob?.cancel()
        if (!streamingLlm.isConfigured) {
            viewModelScope.launch {
                val reply = coach.reply(userMessage, life, healthSnap)
                appendCoach(reply.ifBlank { "I'm here — try a plan command or ask what next." })
            }
            return
        }
        streamJob = viewModelScope.launch {
            _streamingCoach.value = true
            // Seed empty coach bubble that we grow as tokens arrive.
            appendCoach("")
            val tick = brainTick.value
            val horizon = _planning.value.horizonDays
            val system = buildString {
                append("You are Look After, a calm executive coach. Be brief (2-4 sentences). ")
                append(BrainContextPack.systemSummary(tick, horizon))
            }
            val assembled = StringBuilder()
            var emitted = false
            runCatching {
                streamingLlm.streamChat(
                    messages = listOf(
                        StreamingLlmClient.ChatMessage("system", system),
                        StreamingLlmClient.ChatMessage("user", userMessage),
                    ),
                ).collect { delta ->
                    emitted = true
                    assembled.append(delta)
                    replaceLastCoach(assembled.toString())
                }
            }
            if (!emitted || assembled.isBlank()) {
                val fallback = coach.reply(userMessage, life, healthSnap)
                replaceLastCoach(
                    fallback.ifBlank { "I'm here — try a plan command or ask what next." },
                )
            }
            _streamingCoach.value = false
            // Final stream snapshot to disk + history (once).
            planningStore.save(_planning.value)
            val finalText = assembled.toString().ifBlank {
                _planning.value.messages.lastOrNull {
                    it.speaker == com.lookafter.core.planning.PlanningSpeaker.COACH
                }?.text.orEmpty()
            }
            if (finalText.isNotBlank()) {
                recordCoachHistory(
                    CoachHistoryIntent.Record(CoachHistoryEngine.fromCoachReply(finalText)),
                )
            }
        }
    }

    private fun appendCoach(text: String) {
        persistPlanning(
            PlanningConversationEngine.reduce(
                _planning.value,
                PlanningConversationIntent.CoachReply(text),
            ).state,
        )
        if (text.isNotBlank()) {
            recordCoachHistory(
                CoachHistoryIntent.Record(CoachHistoryEngine.fromCoachReply(text)),
            )
        }
    }

    private fun replaceLastCoach(text: String) {
        val msgs = _planning.value.messages.toMutableList()
        val lastCoach = msgs.indexOfLast {
            it.speaker == com.lookafter.core.planning.PlanningSpeaker.COACH
        }
        if (lastCoach >= 0) {
            msgs[lastCoach] = msgs[lastCoach].copy(text = text)
            // Don't thrash disk on every token — memory only; finalized in streamCoachReply.
            _planning.value = _planning.value.copy(messages = msgs)
        } else {
            appendCoach(text)
        }
    }

    fun acceptPendingPlan() {
        viewModelScope.launch {
            val pending = _planning.value.pending ?: return@launch
            if (pending.accepted != null) return@launch
            val intents = PlanningConversationEngine.intentsForPending(pending, engine.currentState)
            intents.forEach { engine.process(it) }
            persistPlanning(
                PlanningConversationEngine.reduce(
                    _planning.value,
                    PlanningConversationIntent.AcceptPending,
                ).state,
            )
            recordCoachHistory(
                CoachHistoryIntent.Record(
                    CoachHistoryEngine.fromPlanOutcome(
                        accepted = true,
                        summary = pending.proposal.summary,
                        mutationCount = pending.proposal.mutations.size,
                    ),
                ),
            )
            _lastSyncMessage.value = "Applied ${intents.size} plan change(s)"
            TodayWidgetUpdater.requestUpdate(getApplication())
        }
    }

    fun rejectPendingPlan() {
        val pending = _planning.value.pending
        persistPlanning(
            PlanningConversationEngine.reduce(
                _planning.value,
                PlanningConversationIntent.RejectPending,
            ).state,
        )
        if (pending != null && pending.accepted == null) {
            recordCoachHistory(
                CoachHistoryIntent.Record(
                    CoachHistoryEngine.fromPlanOutcome(
                        accepted = false,
                        summary = pending.proposal.summary,
                        mutationCount = pending.proposal.mutations.size,
                    ),
                ),
            )
        }
        _lastSyncMessage.value = "Plan discarded"
    }

    fun clearPlanningConversation() {
        // Chat only — pinned coach history survives.
        persistPlanning(
            PlanningConversationEngine.reduce(
                _planning.value,
                PlanningConversationIntent.Clear,
            ).state,
        )
    }

    fun createBodyDoubleRoom(displayName: String) {
        val next = BodyDoubleRoomEngine.reduce(
            _bodyDoubleRoom.value,
            BodyDoubleRoomIntent.Create(
                displayName = displayName,
                useCamera = _cameraBodyDouble.value,
            ),
        )
        _bodyDoubleRoom.value = next
        bindWebRtc(next.localPeerId)
    }

    fun joinBodyDoubleRoom(roomId: String, displayName: String) {
        val next = BodyDoubleRoomEngine.reduce(
            _bodyDoubleRoom.value,
            BodyDoubleRoomIntent.Join(
                roomId = roomId,
                displayName = displayName,
                useCamera = _cameraBodyDouble.value,
            ),
        )
        _bodyDoubleRoom.value = next
        bindWebRtc(next.localPeerId)
    }

    fun demoConnectBodyDoubleRoom() {
        val before = _bodyDoubleRoom.value
        var next = BodyDoubleRoomEngine.demoConnect(before)
        // Drive WebRTC offer/answer over the room signal bus (simulator or native).
        val remote = next.remotePeers.firstOrNull()
        val rtc = webRtc
        if (rtc != null && remote != null) {
            rtc.startAsOfferer(remote.id)
            // Feed simulated remote answer path: controller also emits local signals into room.
            next.signals
                .filter { it.fromPeerId != next.localPeerId }
                .forEach { rtc.handleRemoteSignal(it) }
            // Local loopback: treat our offer as remote for the answer path
            next.signals
                .filter { it.type == BodyDoubleSignalType.OFFER && it.fromPeerId == next.localPeerId }
                .lastOrNull()
                ?.let { offer ->
                    // Peer B simulation already done in demoConnect; mark connected.
                    next = BodyDoubleRoomEngine.reduce(
                        next,
                        BodyDoubleRoomIntent.MarkConnected(remote.id),
                    )
                }
            viewModelScope.launch {
                rtc.connectionState.collect { _webRtcState.value = it }
            }
        }
        _bodyDoubleRoom.value = next
    }

    fun leaveBodyDoubleRoom() {
        webRtc?.close()
        webRtc = null
        _webRtcState.value = WebRtcPeerController.ConnectionState.CLOSED
        _bodyDoubleRoom.value = BodyDoubleRoomEngine.reduce(
            _bodyDoubleRoom.value,
            BodyDoubleRoomIntent.Leave,
        )
    }

    private fun bindWebRtc(localPeerId: String) {
        webRtc?.close()
        val controller = WebRtcPeerController(
            context = getApplication(),
            ice = iceConfig,
            localPeerId = localPeerId,
        )
        controller.addOutboundListener { signal ->
            _bodyDoubleRoom.value = BodyDoubleRoomEngine.reduce(
                _bodyDoubleRoom.value,
                BodyDoubleRoomIntent.SignalReceived(signal),
            )
        }
        webRtc = controller
        viewModelScope.launch {
            controller.connectionState.collect { _webRtcState.value = it }
        }
    }

    fun signInLocal(displayName: String, email: String = "") {
        authStore.signInLocal(displayName, email)
    }

    fun signInFirebaseAnonymous() {
        viewModelScope.launch {
            FirebaseAuthBridge.signInAnonymously()
                .onSuccess { user -> authStore.applyRemoteUser(user) }
                .onFailure {
                    CrashReporting.recordNonFatal(it, "firebase anonymous sign-in")
                    _lastSyncMessage.value = "Firebase sign-in failed — staying local"
                }
        }
    }

    fun signInFirebaseEmail(email: String, password: String) {
        viewModelScope.launch {
            FirebaseAuthBridge.signInWithEmail(email, password)
                .onSuccess { user -> authStore.applyRemoteUser(user) }
                .onFailure {
                    CrashReporting.recordNonFatal(it, "firebase email sign-in")
                    _lastSyncMessage.value = "Email sign-in failed"
                }
        }
    }

    fun signOut() {
        FirebaseAuthBridge.signOut()
        authStore.signOutToAnonymous()
    }

    fun setSyncEnabled(enabled: Boolean) {
        authStore.setSyncEnabled(enabled)
        if (enabled) {
            pushSync()
        }
    }

    fun pushSync() {
        viewModelScope.launch {
            val userId = authStore.state.value.user?.id ?: return@launch
            syncTransport.push(userId, engine.currentState)
                .onSuccess {
                    authStore.markSyncedNow()
                    _lastSyncMessage.value = "Synced via ${syncTransport.name}"
                    CrashReporting.log("sync push ok ${syncTransport.name}")
                }
                .onFailure {
                    CrashReporting.recordNonFatal(it, "sync push")
                    _lastSyncMessage.value = "Sync failed: ${it.message}"
                }
        }
    }

    fun pullSync() {
        viewModelScope.launch {
            val userId = authStore.state.value.user?.id ?: return@launch
            syncTransport.pull(userId)
                .onSuccess { remote ->
                    if (remote != null) {
                        engine.process(LookAfterIntent.ReplaceState(remote))
                        authStore.markSyncedNow()
                        _lastSyncMessage.value = "Pulled LifeState via ${syncTransport.name}"
                    } else {
                        _lastSyncMessage.value = "No remote snapshot"
                    }
                }
                .onFailure {
                    CrashReporting.recordNonFatal(it, "sync pull")
                    _lastSyncMessage.value = "Pull failed: ${it.message}"
                }
        }
    }

    /**
     * Wipe local LifeState, focus, inbox, coach transcript, and onboarding.
     * Does not delete remote Firebase data (user must do that in console).
     */
    fun factoryReset() {
        viewModelScope.launch {
            planStreamJob?.cancel()
            streamJob?.cancel()
            _streamingPlan.value = false
            _streamingCoach.value = false
            _planDraftPreview.value = null
            engine.process(LookAfterIntent.ReplaceState(LifeState.EMPTY))
            _focus.value = FocusSessionState()
            _inbox.value = InboxState()
            planningStore.clear()
            _planning.value = PlanningConversationState()
            coachHistoryStore.clear()
            _coachHistory.value = CoachHistoryState.EMPTY
            lastAutoHeroKey = null
            _bodyDoubleRoom.value = BodyDoubleRoomState()
            _calendarEvents.value = emptyList()
            _ambientEnabled.value = true
            _cameraBodyDouble.value = false
            systemFocus.releaseFocus()
            ambientAudio.stop()
            app.resetOnboarding()
            _onboarding.value = app.initialOnboarding
            authStore.signOutToAnonymous()
            FirebaseAuthBridge.signOut()
            _lastSyncMessage.value = "Device reset complete"
            CrashReporting.log("factory reset")
            TodayWidgetUpdater.requestUpdate(getApplication())
        }
    }

    /** Write LifeState JSON to cache and return a share [android.content.Intent]. */
    fun exportShareIntent(): android.content.Intent? = runCatching {
        val file = com.lookafter.app.data.DataExportImport.exportToCache(
            getApplication(),
            engine.currentState,
        )
        com.lookafter.app.data.DataExportImport.shareIntent(getApplication(), file)
    }.onFailure {
        CrashReporting.recordNonFatal(it, "export")
        _lastSyncMessage.value = "Export failed"
    }.getOrNull()

    fun exportSuggestedFileName(): String {
        val stamp = java.text.SimpleDateFormat("yyyyMMdd-HHmmss", java.util.Locale.US)
            .format(java.util.Date())
        return "lookafter-life-$stamp.json"
    }

    fun exportToUri(uri: android.net.Uri) {
        viewModelScope.launch {
            com.lookafter.app.data.DataExportImport.writeUri(
                getApplication(),
                uri,
                engine.currentState,
            ).onSuccess {
                _lastSyncMessage.value = "Saved backup to Files"
                CrashReporting.log("export uri ok")
            }.onFailure {
                CrashReporting.recordNonFatal(it, "export uri")
                _lastSyncMessage.value = "Save failed: ${it.message}"
            }
        }
    }

    fun importLifeStateJson(json: String) {
        viewModelScope.launch {
            com.lookafter.app.data.DataExportImport.parseImport(json)
                .onSuccess { imported ->
                    applyImportedState(imported)
                }
                .onFailure {
                    CrashReporting.recordNonFatal(it, "import")
                    _lastSyncMessage.value = "Import failed: ${it.message}"
                }
        }
    }

    fun importFromUri(uri: android.net.Uri) {
        viewModelScope.launch {
            com.lookafter.app.data.DataExportImport.importUri(getApplication(), uri)
                .onSuccess { imported ->
                    applyImportedState(imported)
                }
                .onFailure {
                    CrashReporting.recordNonFatal(it, "import uri")
                    _lastSyncMessage.value = "Import failed: ${it.message}"
                }
        }
    }

    private suspend fun applyImportedState(imported: com.lookafter.core.engine.LifeState) {
        engine.process(LookAfterIntent.ReplaceState(imported))
        val summary = com.lookafter.app.data.DataExportImport.prettySummary(imported)
            .lines()
            .joinToString(" · ") { it.trim() }
            .take(120)
        _lastSyncMessage.value = "Imported backup · $summary"
        CrashReporting.log("import ok")
        TodayWidgetUpdater.requestUpdate(getApplication())
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
