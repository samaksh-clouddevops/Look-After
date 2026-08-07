package com.lookafter.app

import android.app.Application
import android.content.Context
import android.util.Log
import com.lookafter.app.calendar.CompositeCalendarEventsProvider
import com.lookafter.app.calendar.DeviceCalendarEventsProvider
import com.lookafter.app.data.DataStoreLifeStateRepository
import com.lookafter.app.execution.ExecutionService
import com.lookafter.app.health.HealthConnectRepository
import com.lookafter.app.auth.AuthSessionStore
import com.lookafter.app.brain.HttpLlmCoachService
import com.lookafter.app.notifications.LookAfterNotifier
import com.lookafter.core.brain.CoachService
import com.lookafter.core.brain.FallbackCoachService
import com.lookafter.core.brain.OfflineCoachService
import com.lookafter.core.calendar.CalendarEvent
import com.lookafter.core.calendar.CalendarEventsProvider
import com.lookafter.core.calendar.StubCalendarEventsProvider
import com.lookafter.core.engine.LifeEngine
import com.lookafter.core.engine.LifeState
import com.lookafter.core.engine.LifeStateRepository
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.Medication
import com.lookafter.core.models.TaskExpirationPolicy
import com.lookafter.core.models.TaskStatus
import com.lookafter.core.onboarding.OnboardingState
import com.lookafter.core.serialization.LookAfterJson
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneOffset
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Process-scoped application shell.
 *
 * Owns [LifeEngine] + [LifeStateRepository] + [HealthConnectRepository] + calendar.
 * Hydrates persisted state on launch (falls back to a tiny demo schedule on first run).
 */
class LookAfterApplication : Application() {

    private val applicationScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    lateinit var lifeStateRepository: LifeStateRepository
        private set

    lateinit var lifeEngine: LifeEngine
        private set

    lateinit var healthRepository: HealthConnectRepository
        private set

    lateinit var calendarProvider: CalendarEventsProvider
        private set

    lateinit var deviceCalendar: DeviceCalendarEventsProvider
        private set

    lateinit var notifier: LookAfterNotifier
        private set

    lateinit var coachService: CoachService
        private set

    lateinit var authSessionStore: AuthSessionStore
        private set

    val initialOnboarding: OnboardingState
        get() = loadOnboarding()

    private val _restoredFromDisk = MutableStateFlow(false)
    val restoredFromDisk: StateFlow<Boolean> = _restoredFromDisk.asStateFlow()

    private val _hydrationComplete = MutableStateFlow(false)
    val hydrationComplete: StateFlow<Boolean> = _hydrationComplete.asStateFlow()

    override fun onCreate() {
        super.onCreate()
        lifeStateRepository = DataStoreLifeStateRepository.create(this)
        healthRepository = HealthConnectRepository(this)
        deviceCalendar = DeviceCalendarEventsProvider(this)
        calendarProvider = CompositeCalendarEventsProvider(
            device = deviceCalendar,
            fallback = StubCalendarEventsProvider(demoCalendar()),
        )
        notifier = LookAfterNotifier(this).also { it.ensureChannels() }
        authSessionStore = AuthSessionStore(this).also { it.ensureAnonymous() }
        // OpenAI-compatible HTTPS coach when LOOKAFTER_LLM_API_KEY is set; else offline.
        val httpCoach = HttpLlmCoachService(
            apiKey = BuildConfig.LLM_API_KEY,
            baseUrl = BuildConfig.LLM_BASE_URL,
            model = BuildConfig.LLM_MODEL,
        )
        coachService = FallbackCoachService(
            primary = httpCoach,
            fallback = OfflineCoachService(),
        )
        if (httpCoach.isConfigured) {
            Log.i(TAG, "LLM coach configured (model=${BuildConfig.LLM_MODEL})")
        } else {
            Log.i(TAG, "LLM coach offline — set LOOKAFTER_LLM_API_KEY in local.properties")
        }
        lifeEngine = LifeEngine(
            initialState = LifeState.EMPTY,
            repository = lifeStateRepository,
        )
        applicationScope.launch {
            val before = lifeStateRepository.load()
            val restored = before != null
            lifeEngine.hydrate(fallback = demoState())
            _restoredFromDisk.value = restored
            _hydrationComplete.value = true
            Log.i(
                TAG,
                if (restored) {
                    "LifeState restored from DataStore " +
                        "(active=${lifeEngine.currentState.activeTasks.size})"
                } else {
                    "No snapshot — seeded demo LifeState and persisted"
                },
            )
            // Try real HC first; if empty, demo fills Briefing readiness.
            healthRepository.preferDemoFallback = false
            healthRepository.refresh()
            if (healthRepository.summary.value.readinessScore == null) {
                healthRepository.preferDemoFallback = true
                healthRepository.markPermission(granted = true)
                healthRepository.refresh()
            }
            startExecutionService()
        }
    }

    fun persistOnboarding(state: OnboardingState) {
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.edit()
            .putString(KEY_ONBOARDING, LookAfterJson.codec.encodeToString(OnboardingState.serializer(), state))
            .apply()
    }

    private fun loadOnboarding(): OnboardingState {
        val raw = getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_ONBOARDING, null)
            ?: return OnboardingState.fresh
        return runCatching {
            LookAfterJson.codec.decodeFromString(OnboardingState.serializer(), raw)
        }.getOrDefault(OnboardingState.fresh)
    }

    private fun demoCalendar(): List<CalendarEvent> {
        val zone = ZoneOffset.systemDefault()
        val today = LocalDate.now(zone)
        val start = today.atTime(14, 0).atZone(zone).toInstant()
        val end = today.atTime(14, 45).atZone(zone).toInstant()
        return listOf(
            CalendarEvent(
                id = "demo-cal-1",
                title = "Team sync",
                start = start,
                end = end,
            ),
        )
    }

    /** Safe to call repeatedly — service is sticky and self-manages lifecycle. */
    fun startExecutionService() {
        try {
            ExecutionService.start(this)
            Log.i(TAG, "ExecutionService start requested")
        } catch (t: Throwable) {
            Log.w(TAG, "Unable to start ExecutionService", t)
        }
    }

    private fun demoState(): LifeState {
        val zone = ZoneOffset.systemDefault()
        val today = LocalDate.now(zone)
        val now = java.time.ZonedDateTime.now(zone)
        // Live focus block spanning "now" so Phase-7 notification can engage.
        val focusStart = now.minusMinutes(10).toInstant()
        val focusEnd = now.plusMinutes(50).toInstant()
        val liveFocus = LifeTask(
            id = "demo-live-focus",
            title = "Deep work session",
            durationMinutes = 60,
            constraintType = ConstraintType.ANCHORED,
            status = TaskStatus.IN_PROGRESS,
            expirationPolicy = TaskExpirationPolicy.Infinite,
            scheduledDate = today,
            scheduledStart = focusStart,
            scheduledEnd = focusEnd,
        )
        val nextFlexible = LifeTask(
            id = "demo-next-flex",
            title = "Inbox triage",
            durationMinutes = 30,
            constraintType = ConstraintType.FLEXIBLE,
            status = TaskStatus.PENDING,
            expirationPolicy = TaskExpirationPolicy.EndOfDay,
            scheduledDate = today,
            scheduledStart = focusEnd.plusSeconds(5 * 60),
            scheduledEnd = focusEnd.plusSeconds(35 * 60),
        )
        val morningMed = Medication(
            id = "demo-med-mag",
            name = "Magnesium",
            dosage = "200mg",
            scheduledTime = LocalTime.of(8, 0),
        )
        val eveningMed = Medication(
            id = "demo-med-vitd",
            name = "Vitamin D",
            dosage = "5000 IU",
            scheduledTime = LocalTime.of(20, 0),
        )
        return LifeState(
            activeTasks = listOf(liveFocus, nextFlexible),
            currentDay = today,
            medications = listOf(morningMed, eveningMed),
            medicationsLastResetDay = today,
        )
    }

    companion object {
        private const val TAG = "LookAfterApp"
        private const val PREFS = "lookafter_app"
        private const val KEY_ONBOARDING = "onboarding_json"
    }
}
