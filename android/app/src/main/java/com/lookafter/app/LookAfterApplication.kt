package com.lookafter.app

import android.app.Application
import android.util.Log
import com.lookafter.app.data.DataStoreLifeStateRepository
import com.lookafter.core.engine.LifeEngine
import com.lookafter.core.engine.LifeState
import com.lookafter.core.engine.LifeStateRepository
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.TaskExpirationPolicy
import com.lookafter.core.models.TaskStatus
import java.time.LocalDate
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
 * Owns [LifeEngine] + [LifeStateRepository]. Hydrates persisted state on launch
 * (falls back to a tiny demo schedule on first run).
 */
class LookAfterApplication : Application() {

    private val applicationScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    lateinit var lifeStateRepository: LifeStateRepository
        private set

    lateinit var lifeEngine: LifeEngine
        private set

    private val _restoredFromDisk = MutableStateFlow(false)
    val restoredFromDisk: StateFlow<Boolean> = _restoredFromDisk.asStateFlow()

    private val _hydrationComplete = MutableStateFlow(false)
    val hydrationComplete: StateFlow<Boolean> = _hydrationComplete.asStateFlow()

    override fun onCreate() {
        super.onCreate()
        lifeStateRepository = DataStoreLifeStateRepository.create(this)
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
        }
    }

    private fun demoState(): LifeState {
        val zone = ZoneOffset.UTC
        val yesterday = LocalDate.now(zone).minusDays(1)
        val meal = LifeTask(
            id = "demo-dinner",
            title = "Dinner (EndOfDay)",
            durationMinutes = 45,
            constraintType = ConstraintType.FLEXIBLE,
            status = TaskStatus.PENDING,
            expirationPolicy = TaskExpirationPolicy.EndOfDay,
            scheduledDate = yesterday,
            scheduledStart = yesterday.atTime(19, 0).atZone(zone).toInstant(),
            scheduledEnd = yesterday.atTime(19, 45).atZone(zone).toInstant(),
        )
        val work = LifeTask(
            id = "demo-deep-work",
            title = "Deep work draft",
            durationMinutes = 90,
            constraintType = ConstraintType.FLEXIBLE,
            status = TaskStatus.PENDING,
            expirationPolicy = TaskExpirationPolicy.Infinite,
            scheduledDate = yesterday,
            scheduledStart = yesterday.atTime(14, 0).atZone(zone).toInstant(),
        )
        return LifeState(
            activeTasks = listOf(meal, work),
            currentDay = yesterday,
        )
    }

    companion object {
        private const val TAG = "LookAfterApp"
    }
}
