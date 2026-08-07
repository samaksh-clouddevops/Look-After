package com.lookafter.app

import android.app.Application
import android.util.Log
import com.lookafter.app.data.DataStoreLifeStateRepository
import com.lookafter.app.execution.ExecutionService
import com.lookafter.app.health.HealthConnectRepository
import com.lookafter.core.engine.LifeEngine
import com.lookafter.core.engine.LifeState
import com.lookafter.core.engine.LifeStateRepository
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.Medication
import com.lookafter.core.models.TaskExpirationPolicy
import com.lookafter.core.models.TaskStatus
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
 * Owns [LifeEngine] + [LifeStateRepository] + [HealthConnectRepository].
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

    private val _restoredFromDisk = MutableStateFlow(false)
    val restoredFromDisk: StateFlow<Boolean> = _restoredFromDisk.asStateFlow()

    private val _hydrationComplete = MutableStateFlow(false)
    val hydrationComplete: StateFlow<Boolean> = _hydrationComplete.asStateFlow()

    override fun onCreate() {
        super.onCreate()
        lifeStateRepository = DataStoreLifeStateRepository.create(this)
        healthRepository = HealthConnectRepository()
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
            // Demo: grant health stub so Briefing readiness paints without HC APK.
            healthRepository.markPermission(granted = true)
            healthRepository.refresh()
            // Let ExecutionService decide whether to promote to foreground.
            startExecutionService()
        }
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
    }
}
