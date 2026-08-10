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
import com.lookafter.app.behavior.BehaviorStore
import com.lookafter.app.creativity.CreativityStore
import com.lookafter.app.cycle.CycleStore
import com.lookafter.app.learning.LearningStore
import com.lookafter.app.travel.TravelStore
import com.lookafter.app.webrtc.RoomSignalingFactory
import com.lookafter.app.webrtc.RoomSignalingTransport
import com.lookafter.app.webrtc.WebRtcPeerController
import com.lookafter.app.widget.TodayWidgetUpdater
import com.lookafter.core.behavior.BehaviorEngine
import com.lookafter.core.behavior.BehaviorIntent
import com.lookafter.core.behavior.BehaviorState
import com.lookafter.core.behavior.Habit
import com.lookafter.core.creativity.CreativeBoard
import com.lookafter.core.creativity.CreativeSpark
import com.lookafter.core.creativity.CreativityEngine
import com.lookafter.core.creativity.CreativityIntent
import com.lookafter.core.creativity.CreativityState
import com.lookafter.core.cycle.CycleEngine
import com.lookafter.core.cycle.CycleIntent
import com.lookafter.core.cycle.CycleLogEntry
import com.lookafter.core.cycle.CycleSnapshot
import com.lookafter.core.cycle.CycleState
import com.lookafter.core.learning.LearningCard
import com.lookafter.core.learning.LearningEngine
import com.lookafter.core.learning.LearningIntent
import com.lookafter.core.learning.LearningState
import com.lookafter.core.learning.LearningTrack
import com.lookafter.core.learning.ReviewGrade
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.TaskStatus
import com.lookafter.core.travel.PackingItem
import com.lookafter.core.travel.TravelEngine
import com.lookafter.core.travel.TravelIntent
import com.lookafter.core.travel.TravelState
import com.lookafter.core.travel.TravelTrip
import java.util.UUID
import com.lookafter.core.adhd.BodyDoublePeer
import com.lookafter.core.adhd.BodyDoubleRoomEngine
import com.lookafter.core.adhd.BodyDoubleRoomIntent
import com.lookafter.core.adhd.BodyDoubleRoomPhase
import com.lookafter.core.adhd.BodyDoubleRoomState
import com.lookafter.core.adhd.BodyDoubleSessionSummary
import com.lookafter.core.adhd.BodyDoubleSignal
import com.lookafter.core.adhd.BodyDoubleSignalType
import com.lookafter.core.adhd.RoomPresence
import com.lookafter.core.adhd.RoomSignalEnvelope
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
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
    private val travelStore: TravelStore = app.travelStore
    private val cycleStore: CycleStore = app.cycleStore
    private val creativityStore: CreativityStore = app.creativityStore
    private val learningStore: LearningStore = app.learningStore
    private val behaviorStore: BehaviorStore = app.behaviorStore
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
    private var roomSignal: RoomSignalingTransport? = null
    private var lastAutoHeroKey: String? = null
    private val lastSignalCount = AtomicInteger(0)
    private val knownRemotePeers = mutableSetOf<String>()
    private var sessionStartedAt: Instant? = null
    private var sessionOfferer: Boolean = false
    private var lastRemoteForOffer: String? = null
    private val sessionReachedConnected = AtomicBoolean(false)
    private val sessionFocusStarted = AtomicBoolean(false)

    private val _travel = MutableStateFlow(app.travelStore.load())
    val travel: StateFlow<TravelState> = _travel.asStateFlow()

    private val _cycle = MutableStateFlow(app.cycleStore.load())
    val cycle: StateFlow<CycleState> = _cycle.asStateFlow()

    private fun persistTravel(next: TravelState) {
        _travel.value = next
        travelStore.save(next)
    }

    private fun persistCycle(next: CycleState) {
        _cycle.value = next
        cycleStore.save(next)
    }

    fun dispatchTravel(intent: TravelIntent) {
        persistTravel(TravelEngine.reduce(_travel.value, intent))
    }

    fun dispatchCycle(intent: CycleIntent) {
        persistCycle(CycleEngine.reduce(_cycle.value, intent))
    }

    fun addTravelTrip(trip: TravelTrip) {
        dispatchTravel(TravelIntent.AddTrip(trip))
    }

    fun deleteTravelTrip(id: String) {
        dispatchTravel(TravelIntent.DeleteTrip(id))
    }

    fun selectTravelTrip(id: String?) {
        dispatchTravel(TravelIntent.SelectTrip(id))
    }

    fun togglePackingItem(tripId: String, itemId: String) {
        dispatchTravel(TravelIntent.TogglePackingItem(tripId, itemId))
    }

    fun addPackingItem(tripId: String, item: PackingItem) {
        dispatchTravel(TravelIntent.AddPackingItem(tripId, item))
    }

    /** Open a trip day on the Today board (week-scrubber / packing scaffolding). */
    fun openTravelDayOnToday(day: LocalDate) {
        viewModelScope.launch {
            engine.process(LookAfterIntent.SetCurrentDay(day))
            _lastSyncMessage.value = "Today set to $day · travel packing"
            TodayWidgetUpdater.requestUpdate(getApplication())
        }
    }

    fun setCycleTracking(enabled: Boolean) {
        dispatchCycle(CycleIntent.SetTrackingEnabled(enabled))
    }

    fun setCyclePeriodStart(day: LocalDate?) {
        dispatchCycle(CycleIntent.SetLastPeriodStart(day))
    }

    fun setCycleLength(days: Int) {
        dispatchCycle(CycleIntent.SetCycleLength(days))
    }

    fun setPeriodLength(days: Int) {
        dispatchCycle(CycleIntent.SetPeriodLength(days))
    }

    fun addCycleLog(entry: CycleLogEntry) {
        dispatchCycle(CycleIntent.AddLog(entry))
    }

    fun deleteCycleLog(id: String) {
        dispatchCycle(CycleIntent.DeleteLog(id))
    }

    private val _creativity = MutableStateFlow(app.creativityStore.load())
    val creativity: StateFlow<CreativityState> = _creativity.asStateFlow()

    private fun persistCreativity(next: CreativityState) {
        _creativity.value = next
        creativityStore.save(next)
    }

    fun dispatchCreativity(intent: CreativityIntent) {
        persistCreativity(CreativityEngine.reduce(_creativity.value, intent))
    }

    fun addCreativeBoard(board: CreativeBoard) {
        dispatchCreativity(CreativityIntent.AddBoard(board))
    }

    fun selectCreativeBoard(id: String?) {
        dispatchCreativity(CreativityIntent.SelectBoard(id))
    }

    fun deleteCreativeBoard(id: String) {
        dispatchCreativity(CreativityIntent.DeleteBoard(id))
    }

    fun addCreativeSpark(spark: CreativeSpark, boardId: String?) {
        dispatchCreativity(CreativityIntent.AddSpark(spark, boardId))
    }

    fun deleteCreativeSpark(id: String) {
        dispatchCreativity(CreativityIntent.DeleteSpark(id))
    }

    fun pinCreativeSpark(id: String, pinned: Boolean) {
        dispatchCreativity(CreativityIntent.PinSpark(id, pinned))
    }

    /** Promote a spark into Inbox/Today as a fluid capture task. */
    fun promoteSparkToCapture(sparkId: String) {
        val spark = _creativity.value.sparks.firstOrNull { it.id == sparkId } ?: return
        val title = spark.title.ifBlank { spark.body.take(80) }.ifBlank { "Creative spark" }
        val task = LifeTask(
            id = UUID.randomUUID().toString(),
            title = title,
            notes = buildString {
                if (spark.body.isNotBlank() && spark.title.isNotBlank()) append(spark.body)
                append(if (isNotEmpty()) "\n" else "")
                append("from creativity · ${spark.kind.label}")
            },
            constraintType = ConstraintType.FLUID,
            status = TaskStatus.PENDING,
            tags = listOf("capture", "creativity") + spark.tags,
            createdAt = Instant.now(),
        )
        viewModelScope.launch {
            engine.process(LookAfterIntent.AddTask(task))
            dispatchCreativity(CreativityIntent.PromoteSparkToCapture(sparkId))
            _lastSyncMessage.value = "Spark → Capture · $title"
            TodayWidgetUpdater.requestUpdate(getApplication())
        }
    }

    private val _learning = MutableStateFlow(app.learningStore.load())
    val learning: StateFlow<LearningState> = _learning.asStateFlow()

    val learningDueCount: Int
        get() = _learning.value.dueCards(
            today = engine.currentState.currentDay ?: LocalDate.now(),
        ).size

    private fun persistLearning(next: LearningState) {
        _learning.value = next
        learningStore.save(next)
    }

    fun dispatchLearning(intent: LearningIntent) {
        persistLearning(LearningEngine.reduce(_learning.value, intent))
    }

    fun addLearningTrack(track: LearningTrack) {
        dispatchLearning(LearningIntent.AddTrack(track))
    }

    fun selectLearningTrack(id: String?) {
        dispatchLearning(LearningIntent.SelectTrack(id))
    }

    fun deleteLearningTrack(id: String) {
        dispatchLearning(LearningIntent.DeleteTrack(id))
    }

    fun addLearningCard(card: LearningCard, trackId: String?) {
        dispatchLearning(LearningIntent.AddCard(card, trackId))
    }

    fun deleteLearningCard(id: String) {
        dispatchLearning(LearningIntent.DeleteCard(id))
    }

    fun reviewLearningCard(cardId: String, grade: ReviewGrade) {
        dispatchLearning(
            LearningIntent.ReviewCard(
                cardId = cardId,
                grade = grade,
                today = engine.currentState.currentDay ?: LocalDate.now(),
            ),
        )
    }

    private val _behavior = MutableStateFlow(app.behaviorStore.load())
    val behavior: StateFlow<BehaviorState> = _behavior.asStateFlow()

    private fun persistBehavior(next: BehaviorState) {
        _behavior.value = next
        behaviorStore.save(next)
    }

    fun dispatchBehavior(intent: BehaviorIntent) {
        persistBehavior(BehaviorEngine.reduce(_behavior.value, intent))
    }

    fun addHabit(habit: Habit) {
        dispatchBehavior(BehaviorIntent.AddHabit(habit))
    }

    fun toggleHabitCheckIn(id: String) {
        val day = engine.currentState.currentDay ?: LocalDate.now()
        dispatchBehavior(BehaviorIntent.ToggleCheckIn(id = id, day = day))
    }

    fun archiveHabit(id: String) {
        dispatchBehavior(BehaviorIntent.ArchiveHabit(id, archived = true))
    }

    fun deleteHabit(id: String) {
        dispatchBehavior(BehaviorIntent.DeleteHabit(id))
    }

    val roomSignalingName: String
        get() = roomSignal?.name ?: "none"

    private val _videoEnabled = MutableStateFlow(true)
    val roomVideoEnabled: StateFlow<Boolean> = _videoEnabled.asStateFlow()

    private val _audioEnabled = MutableStateFlow(false)
    val roomAudioEnabled: StateFlow<Boolean> = _audioEnabled.asStateFlow()

    private val _autoFocusOnConnect = MutableStateFlow(true)
    val autoFocusOnConnect: StateFlow<Boolean> = _autoFocusOnConnect.asStateFlow()

    private val _lastSessionSummary = MutableStateFlow<BodyDoubleSessionSummary?>(null)
    val lastSessionSummary: StateFlow<BodyDoubleSessionSummary?> = _lastSessionSummary.asStateFlow()

    private val _roomStatusMessage = MutableStateFlow<String?>(null)
    val roomStatusMessage: StateFlow<String?> = _roomStatusMessage.asStateFlow()

    fun setRoomVideoEnabled(enabled: Boolean) {
        _videoEnabled.value = enabled
        webRtc?.setLocalVideoEnabled(enabled)
    }

    fun setRoomAudioEnabled(enabled: Boolean) {
        _audioEnabled.value = enabled
        webRtc?.setLocalAudioEnabled(enabled)
    }

    fun setAutoFocusOnConnect(enabled: Boolean) {
        _autoFocusOnConnect.value = enabled
    }

    fun clearSessionSummary() {
        _lastSessionSummary.value = null
    }

    fun reconnectBodyDoubleRoom() {
        val remote = lastRemoteForOffer
            ?: _bodyDoubleRoom.value.remotePeers.firstOrNull()?.id
        if (remote.isNullOrBlank()) {
            _roomStatusMessage.value = "No partner to reconnect — wait or use Demo join"
            return
        }
        _roomStatusMessage.value = "Reconnecting…"
        _webRtcState.value = WebRtcPeerController.ConnectionState.SIGNALING
        webRtc?.reconnectAsOfferer(remote)
    }

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

    private val _webRtcBackend =
        MutableStateFlow(WebRtcPeerController.Backend.SIMULATOR)
    val webRtcBackend: StateFlow<WebRtcPeerController.Backend> =
        _webRtcBackend.asStateFlow()

    private var planStreamJob: Job? = null

    val auth = authStore.state
    val firebaseAuthAvailable: Boolean get() = FirebaseAuthBridge.isAvailable()
    val llmPlanConfigured: Boolean get() = planService.isConfigured
    val streamingLlmConfigured: Boolean get() = streamingLlm.isConfigured
    val webRtcNativeAvailable: Boolean
        get() = com.lookafter.app.webrtc.NativeWebRtcSession.isAvailable()

    fun attachWebRtcLocalRenderer(renderer: org.webrtc.SurfaceViewRenderer) {
        webRtc?.attachLocalRenderer(renderer)
    }

    fun attachWebRtcRemoteRenderer(renderer: org.webrtc.SurfaceViewRenderer) {
        webRtc?.attachRemoteRenderer(renderer)
    }

    fun webRtcEglContext(): org.webrtc.EglBase.Context? = webRtc?.eglContext

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
    val healthHistory = healthRepo.history
    val healthRolling = healthRepo.rollingAverages
    val healthPermissionGranted: StateFlow<Boolean> = healthRepo.permissionGranted
    val healthUsingDemo: StateFlow<Boolean> = healthRepo.usingDemo
    val healthRequiredPermissions: Set<String> get() = healthRepo.requiredPermissions()

    val cycleSnapshot: StateFlow<CycleSnapshot> = combine(_cycle, state) { c, life ->
        CycleEngine.snapshot(c, today = life.currentDay ?: LocalDate.now())
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), CycleSnapshot())

    val insights: StateFlow<InsightsSnapshot> = combine(
        state,
        health,
        healthHistory,
        healthRolling,
    ) { life, h, hist, rolling ->
        InsightsEngine.compute(
            state = life,
            health = h,
            healthHistory = hist,
            rollingHealth = rolling,
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), InsightsSnapshot.EMPTY)

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

    val executiveCapacity: StateFlow<ExecutiveCapacity> =
        combine(state, health, brainTick, cycleSnapshot) { life, h, tick, cycle ->
            ExecutiveCapacityEngine.compute(
                state = life,
                health = h,
                world = tick.world,
                cycleModifier = cycle.capacityModifier,
                cyclePhaseLabel = cycle.phaseLabel.takeIf { cycle.trackingEnabled },
            )
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
        teardownRoomSession(publishLeave = true)
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
                    for (intent in simple.intents) {
                        engine.process(intent)
                    }
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
            for (intent in intents) {
                engine.process(intent)
            }
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
        teardownRoomSession(publishLeave = false)
        _lastSessionSummary.value = null
        _roomStatusMessage.value = null
        val next = BodyDoubleRoomEngine.reduce(
            _bodyDoubleRoom.value,
            BodyDoubleRoomIntent.Create(
                displayName = displayName,
                useCamera = _cameraBodyDouble.value,
            ),
        )
        _bodyDoubleRoom.value = next
        startRoomSession(
            roomId = next.roomId.orEmpty(),
            localPeerId = next.localPeerId,
            displayName = displayName,
            isOfferer = true,
        )
        val msg = "Room ${next.roomId} · signal ${roomSignal?.name}"
        _lastSyncMessage.value = msg
        _roomStatusMessage.value = "Share code ${next.roomId} — waiting for partner"
    }

    fun joinBodyDoubleRoom(roomId: String, displayName: String) {
        val trimmed = roomId.trim()
        if (trimmed.isEmpty()) {
            _roomStatusMessage.value = "Enter a room code to join"
            _bodyDoubleRoom.value = _bodyDoubleRoom.value.copy(lastError = "Room code required")
            return
        }
        teardownRoomSession(publishLeave = false)
        _lastSessionSummary.value = null
        _roomStatusMessage.value = null
        val next = BodyDoubleRoomEngine.reduce(
            _bodyDoubleRoom.value,
            BodyDoubleRoomIntent.Join(
                roomId = trimmed,
                displayName = displayName,
                useCamera = _cameraBodyDouble.value,
            ),
        )
        if (next.phase == BodyDoubleRoomPhase.FAILED || next.roomId.isNullOrBlank()) {
            _roomStatusMessage.value = next.lastError ?: "Could not join room"
            _bodyDoubleRoom.value = next
            return
        }
        _bodyDoubleRoom.value = next
        startRoomSession(
            roomId = next.roomId.orEmpty(),
            localPeerId = next.localPeerId,
            displayName = displayName,
            isOfferer = false,
        )
        val msg = "Joined ${next.roomId} · signal ${roomSignal?.name}"
        _lastSyncMessage.value = msg
        _roomStatusMessage.value = "Connecting to host…"
    }

    fun demoConnectBodyDoubleRoom() {
        val before = _bodyDoubleRoom.value
        var next = BodyDoubleRoomEngine.demoConnect(before)
        val remote = next.remotePeers.firstOrNull()
        val rtc = webRtc
        if (rtc != null && remote != null) {
            lastRemoteForOffer = remote.id
            rtc.startAsOfferer(remote.id)
            next.signals
                .filter { it.fromPeerId != next.localPeerId }
                .forEach { rtc.handleRemoteSignal(it) }
            next.signals
                .filter { it.type == BodyDoubleSignalType.OFFER && it.fromPeerId == next.localPeerId }
                .lastOrNull()
                ?.let {
                    next = BodyDoubleRoomEngine.reduce(
                        next,
                        BodyDoubleRoomIntent.MarkConnected(remote.id),
                    )
                }
            // Simulator often jumps straight to CONNECTED.
            if (rtc.connectionState.value == WebRtcPeerController.ConnectionState.CONNECTED ||
                next.phase == BodyDoubleRoomPhase.CONNECTED
            ) {
                sessionReachedConnected.set(true)
                _webRtcState.value = WebRtcPeerController.ConnectionState.CONNECTED
                maybeStartFocusFromRoom()
            }
        }
        _bodyDoubleRoom.value = next
        _lastSyncMessage.value = "Demo partner joined (local loopback)"
        _roomStatusMessage.value = "Demo partner connected"
    }

    fun leaveBodyDoubleRoom() {
        finalizeSessionSummary(leftReason = "leave")
        teardownRoomSession(publishLeave = true)
        _bodyDoubleRoom.value = BodyDoubleRoomEngine.reduce(
            _bodyDoubleRoom.value,
            BodyDoubleRoomIntent.Leave,
        )
        _lastSyncMessage.value = "Left body-double room"
        _roomStatusMessage.value = null
    }

    private fun startRoomSession(
        roomId: String,
        localPeerId: String,
        displayName: String,
        isOfferer: Boolean,
    ) {
        if (roomId.isBlank()) return
        knownRemotePeers.clear()
        lastSignalCount.set(0)
        sessionStartedAt = Instant.now()
        sessionOfferer = isOfferer
        lastRemoteForOffer = null
        sessionReachedConnected.set(false)
        sessionFocusStarted.set(false)
        _videoEnabled.value = true
        _audioEnabled.value = false
        bindWebRtc(localPeerId)
        val signaling = RoomSignalingFactory.create(getApplication(), preferFirestore = true)
        roomSignal = signaling
        signaling.addListener { envelope -> onRoomEnvelope(envelope, localPeerId, isOfferer) }
        signaling.join(
            roomId = roomId,
            presence = RoomPresence(
                peerId = localPeerId,
                displayName = displayName,
                joinedAt = Instant.now(),
            ),
        )
        // Presence beacon so peers see us.
        signaling.publish(
            BodyDoubleSignal(
                type = BodyDoubleSignalType.PRESENCE,
                fromPeerId = localPeerId,
                payload = displayName,
                at = Instant.now(),
            ),
        )
    }

    private fun finalizeSessionSummary(leftReason: String) {
        val started = sessionStartedAt ?: return
        val room = _bodyDoubleRoom.value
        val summary = BodyDoubleSessionSummary.fromSession(
            roomId = room.roomId.orEmpty(),
            startedAt = started,
            endedAt = Instant.now(),
            peers = room.peers,
            webRtcBackend = _webRtcBackend.value.name.lowercase(),
            signaling = roomSignal?.name ?: "none",
            reachedConnected = sessionReachedConnected.get() ||
                _webRtcState.value == WebRtcPeerController.ConnectionState.CONNECTED,
            focusStarted = sessionFocusStarted.get(),
            leftReason = leftReason,
        )
        _lastSessionSummary.value = summary
        sessionStartedAt = null
    }

    private fun onRoomEnvelope(
        envelope: RoomSignalEnvelope,
        localPeerId: String,
        isOfferer: Boolean,
    ) {
        // Presence → peer list
        envelope.presence
            .filter { !it.left && it.peerId != localPeerId }
            .forEach { p ->
                if (knownRemotePeers.add(p.peerId)) {
                    lastRemoteForOffer = p.peerId
                    _bodyDoubleRoom.value = BodyDoubleRoomEngine.reduce(
                        _bodyDoubleRoom.value,
                        BodyDoubleRoomIntent.PeerJoined(
                            BodyDoublePeer(
                                id = p.peerId,
                                displayName = p.displayName,
                                isLocal = false,
                            ),
                        ),
                    )
                    _roomStatusMessage.value = "${p.displayName} joined — negotiating…"
                    // First remote: creator offers
                    if (isOfferer) {
                        webRtc?.startAsOfferer(p.peerId)
                    }
                }
            }
        envelope.presence.filter { it.left && it.peerId != localPeerId }.forEach { p ->
            if (knownRemotePeers.remove(p.peerId)) {
                _bodyDoubleRoom.value = BodyDoubleRoomEngine.reduce(
                    _bodyDoubleRoom.value,
                    BodyDoubleRoomIntent.PeerLeft(p.peerId),
                )
            }
        }
        // Only process new signals from others
        val all = envelope.signals
        val start = lastSignalCount.get().coerceAtMost(all.size)
        if (start < all.size) {
            lastSignalCount.set(all.size)
            all.subList(start, all.size)
                .filter { it.fromPeerId != localPeerId }
                .forEach { signal ->
                    _bodyDoubleRoom.value = BodyDoubleRoomEngine.reduce(
                        _bodyDoubleRoom.value,
                        BodyDoubleRoomIntent.SignalReceived(signal),
                    )
                    webRtc?.handleRemoteSignal(signal)
                    if (signal.type == BodyDoubleSignalType.HANGUP) {
                        _roomStatusMessage.value = "Partner left"
                        // Don't auto-finalize; user can leave to see summary.
                    }
                }
        }
    }

    private fun teardownRoomSession(publishLeave: Boolean) {
        val peerId = _bodyDoubleRoom.value.localPeerId
        if (publishLeave && peerId.isNotBlank()) {
            runCatching { roomSignal?.leave(peerId) }
        }
        runCatching { roomSignal?.close() }
        roomSignal = null
        webRtc?.close()
        webRtc = null
        knownRemotePeers.clear()
        lastSignalCount.set(0)
        _webRtcState.value = WebRtcPeerController.ConnectionState.CLOSED
        _webRtcBackend.value = WebRtcPeerController.Backend.SIMULATOR
    }

    private fun bindWebRtc(localPeerId: String) {
        webRtc?.close()
        val controller = WebRtcPeerController(
            context = getApplication(),
            ice = iceConfig,
            localPeerId = localPeerId,
            enableVideo = true,
            enableAudio = false,
        )
        controller.addOutboundListener { signal: BodyDoubleSignal ->
            _bodyDoubleRoom.value = BodyDoubleRoomEngine.reduce(
                _bodyDoubleRoom.value,
                BodyDoubleRoomIntent.SignalReceived(signal),
            )
            // Fan-out to multi-device bus (skip pure local hangup noise after leave).
            roomSignal?.publish(signal)
        }
        webRtc = controller
        // Apply current mute prefs
        controller.setLocalVideoEnabled(_videoEnabled.value)
        controller.setLocalAudioEnabled(_audioEnabled.value)
        viewModelScope.launch {
            controller.connectionState.collect { state ->
                _webRtcState.value = state
                when (state) {
                    WebRtcPeerController.ConnectionState.CONNECTED -> {
                        sessionReachedConnected.set(true)
                        _roomStatusMessage.value = "Connected"
                        _bodyDoubleRoom.value = BodyDoubleRoomEngine.reduce(
                            _bodyDoubleRoom.value,
                            lastRemoteForOffer?.let { BodyDoubleRoomIntent.MarkConnected(it) }
                                ?: BodyDoubleRoomIntent.SignalReceived(
                                    BodyDoubleSignal(
                                        type = BodyDoubleSignalType.PRESENCE,
                                        fromPeerId = localPeerId,
                                        at = Instant.now(),
                                    ),
                                ),
                        )
                        maybeStartFocusFromRoom()
                    }
                    WebRtcPeerController.ConnectionState.FAILED -> {
                        _roomStatusMessage.value = "Connection failed — try Reconnect"
                        _bodyDoubleRoom.value = BodyDoubleRoomEngine.reduce(
                            _bodyDoubleRoom.value,
                            BodyDoubleRoomIntent.Fail("WebRTC failed"),
                        )
                    }
                    WebRtcPeerController.ConnectionState.CONNECTING,
                    WebRtcPeerController.ConnectionState.SIGNALING,
                    -> _roomStatusMessage.value = "Negotiating media…"
                    else -> Unit
                }
            }
        }
        viewModelScope.launch {
            controller.backend.collect { _webRtcBackend.value = it }
        }
    }

    private fun maybeStartFocusFromRoom() {
        if (!_autoFocusOnConnect.value) return
        if (sessionFocusStarted.getAndSet(true)) return
        if (focus.value.phase == FocusSessionPhase.RUNNING) return
        startFocusForHero(emergency = false)
        _roomStatusMessage.value = "Connected · focus started"
        _lastSyncMessage.value = "Body double connected · focus running"
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
            travelStore.clear()
            _travel.value = TravelState.EMPTY
            cycleStore.clear()
            _cycle.value = CycleState.EMPTY
            creativityStore.clear()
            _creativity.value = creativityStore.load() // re-seed default boards
            learningStore.clear()
            _learning.value = learningStore.load() // re-seed default track
            behaviorStore.clear()
            _behavior.value = BehaviorState.EMPTY
            lastAutoHeroKey = null
            teardownRoomSession(publishLeave = false)
            _bodyDoubleRoom.value = BodyDoubleRoomState()
            _lastSessionSummary.value = null
            _roomStatusMessage.value = null
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
