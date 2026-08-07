package com.lookafter.core.engine

import com.lookafter.core.models.CascadeActionKind
import com.lookafter.core.models.CascadeActionLog
import com.lookafter.core.models.ConflictCascadeAction
import com.lookafter.core.models.ConflictCascadeDecision
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.Medication
import com.lookafter.core.models.Priority
import com.lookafter.core.models.TaskStatus
import com.lookafter.core.planning.ConflictResolutionCascade
import com.lookafter.core.planning.DayScheduleReconciler
import java.time.Instant
import java.time.LocalDate
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * Central UDF dispatcher for Look After physics.
 *
 * - Exposes immutable [state] via [StateFlow]
 * - Reduces [LookAfterIntent] into pure [LifeState] copies
 * - Wires Phase-1 engines ([DayScheduleReconciler], [ConflictResolutionCascade])
 * - Persists via [LifeStateRepository] **outside** the mutex on [Dispatchers.IO]
 *
 * Zero Android dependencies — safe for JVM unit tests and multiplatform hosts.
 */
class LifeEngine(
    initialState: LifeState = LifeState.EMPTY,
    private val repository: LifeStateRepository? = null,
) {
    private val mutex = Mutex()
    private val _state = MutableStateFlow(initialState)
    val state: StateFlow<LifeState> = _state.asStateFlow()

    val currentState: LifeState get() = _state.value

    /**
     * Hydrate from [repository] if present. Falls back to [fallback] when load
     * returns null (first launch / corrupt snapshot).
     *
     * Disk I/O runs on [Dispatchers.IO] and **never** holds [mutex].
     * Call once at process start before UI binds to [state].
     */
    suspend fun hydrate(fallback: LifeState = LifeState.EMPTY): LifeState {
        val loaded = withContext(Dispatchers.IO) {
            repository?.load()
        }
        val next = loaded ?: fallback
        mutex.withLock {
            _state.value = next
        }
        // First launch: materialize a durable snapshot without holding the reduce lock.
        if (loaded == null && repository != null) {
            withContext(Dispatchers.IO) {
                repository.save(next)
            }
        }
        return next
    }

    /**
     * Atomically reduce [intent] against the current universe and emit a new state.
     *
     * 1. [mutex] only guards pure functional reduction + in-memory emission.
     * 2. Repository I/O runs after the lock is released, on [Dispatchers.IO].
     */
    suspend fun process(intent: LookAfterIntent) {
        val newState = mutex.withLock {
            val reduced = reduce(_state.value, intent)
            _state.value = reduced
            reduced
        }
        if (repository != null) {
            withContext(Dispatchers.IO) {
                repository.save(newState)
            }
        }
    }

    /** Pure reducer — exposed for tests that want to assert transitions without the flow. */
    fun reduce(current: LifeState, intent: LookAfterIntent): LifeState = when (intent) {
        is LookAfterIntent.AddTask -> reduceAddTask(current, intent.task)
        is LookAfterIntent.DeleteTask -> reduceDeleteTask(current, intent.id)
        is LookAfterIntent.UpdateTask -> reduceUpdateTask(current, intent.task)
        is LookAfterIntent.ParkTask -> reduceParkTask(current, intent.id, intent.reason)
        is LookAfterIntent.MoveToSomeday -> reduceMoveToSomeday(current, intent.id)
        is LookAfterIntent.UnparkTask -> reduceUnparkTask(current, intent.id)
        is LookAfterIntent.CompleteTask -> reduceCompleteTask(current, intent.id, intent.completedAt)
        is LookAfterIntent.CommitHypotheticalTasks -> reduceCommitHypothetical(current, intent)
        is LookAfterIntent.TriggerMidnightSweep -> reduceMidnightSweep(current, intent)
        is LookAfterIntent.RunCascadeReconciliation -> reduceCascade(current, intent)
        is LookAfterIntent.ReplaceState -> intent.state
        is LookAfterIntent.SetHighLoadStreak ->
            current.copy(consecutiveHighLoadDays = intent.days.coerceAtLeast(0))
        is LookAfterIntent.AddMedication -> reduceAddMedication(current, intent.medication)
        is LookAfterIntent.UpdateMedication -> reduceUpdateMedication(current, intent.medication)
        is LookAfterIntent.DeleteMedication -> reduceDeleteMedication(current, intent.id)
        is LookAfterIntent.TakeMedication ->
            reduceTakeMedication(current, intent.id, intent.takenAt, intent.taken)
        is LookAfterIntent.ResetMedicationsForNewDay ->
            reduceResetMedications(current, intent.day)
        is LookAfterIntent.ReplaceMedications ->
            current.copy(medications = intent.medications)
    }

    // -------------------------------------------------------------------------
    // Reducers
    // -------------------------------------------------------------------------

    private fun reduceAddTask(current: LifeState, task: LifeTask): LifeState {
        val without = stripTask(current, task.id)
        return if (task.priority == Priority.SOMEDAY) {
            without.copy(somedayVault = without.somedayVault + task)
        } else {
            without.copy(activeTasks = without.activeTasks + task)
        }
    }

    private fun reduceDeleteTask(current: LifeState, id: String): LifeState = stripTask(current, id)

    private fun reduceUpdateTask(current: LifeState, task: LifeTask): LifeState {
        fun List<LifeTask>.replace(): List<LifeTask> = map { if (it.id == task.id) task else it }
        return when {
            current.activeTasks.any { it.id == task.id } ->
                current.copy(activeTasks = current.activeTasks.replace())
            current.parkedQueue.any { it.id == task.id } ->
                current.copy(parkedQueue = current.parkedQueue.replace())
            current.somedayVault.any { it.id == task.id } ->
                current.copy(somedayVault = current.somedayVault.replace())
            else -> reduceAddTask(current, task)
        }
    }

    private fun reduceParkTask(current: LifeState, id: String, reason: String): LifeState {
        val task = current.taskById(id) ?: return current
        val parked = task.copy(
            scheduledStart = null,
            scheduledEnd = null,
            scheduledDate = null,
            constraintType = ConstraintType.FLUID,
            tags = (task.tags + "parked").distinct(),
            updatedAt = Instant.now(),
        )
        val stripped = stripTask(current, id)
        val log = CascadeActionLog(
            taskId = id,
            action = CascadeActionKind.PARKED,
            reason = reason,
        )
        return stripped.copy(
            parkedQueue = stripped.parkedQueue + parked,
            actionLogs = stripped.actionLogs + log,
        )
    }

    private fun reduceMoveToSomeday(current: LifeState, id: String): LifeState {
        val task = current.taskById(id) ?: return current
        val vaulted = task.copy(priority = Priority.SOMEDAY, updatedAt = Instant.now())
        val stripped = stripTask(current, id)
        return stripped.copy(somedayVault = stripped.somedayVault + vaulted)
    }

    private fun reduceUnparkTask(current: LifeState, id: String): LifeState {
        val task = current.parkedQueue.firstOrNull { it.id == id } ?: return current
        val active = task.copy(
            tags = task.tags.filterNot { it == "parked" },
            updatedAt = Instant.now(),
        )
        return current.copy(
            parkedQueue = current.parkedQueue.filterNot { it.id == id },
            activeTasks = current.activeTasks + active,
        )
    }

    private fun reduceCompleteTask(
        current: LifeState,
        id: String,
        completedAt: Instant,
    ): LifeState {
        val task = current.taskById(id) ?: return current
        if (task.status == TaskStatus.COMPLETED) return current
        val completed = task.copy(
            status = TaskStatus.COMPLETED,
            completedAt = completedAt,
            updatedAt = completedAt,
        )
        val log = CascadeActionLog(
            taskId = id,
            action = CascadeActionKind.FOCUS_COMPLETED,
            reason = "user_complete",
            focusMinutes = task.durationMinutes.coerceAtLeast(0),
            recordedAt = completedAt,
        )
        fun List<LifeTask>.replaceOrKeep(): List<LifeTask> =
            map { if (it.id == id) completed else it }

        return when {
            current.activeTasks.any { it.id == id } ->
                current.copy(
                    activeTasks = current.activeTasks.replaceOrKeep(),
                    actionLogs = current.actionLogs + log,
                )
            current.parkedQueue.any { it.id == id } ->
                current.copy(
                    parkedQueue = current.parkedQueue.replaceOrKeep(),
                    actionLogs = current.actionLogs + log,
                )
            current.somedayVault.any { it.id == id } ->
                current.copy(
                    somedayVault = current.somedayVault.replaceOrKeep(),
                    actionLogs = current.actionLogs + log,
                )
            else -> current
        }
    }

    /**
     * Inject what-if tasks into the live active pool and re-run the cascade.
     * SimulationEngine is dry-run only — this is the real commit path.
     */
    private fun reduceCommitHypothetical(
        current: LifeState,
        intent: LookAfterIntent.CommitHypotheticalTasks,
    ): LifeState {
        if (intent.tasks.isEmpty()) return current
        var next = current
        for (task in intent.tasks) {
            next = reduceAddTask(next, task)
        }
        val day = intent.day
            ?: intent.tasks.firstNotNullOfOrNull { it.scheduledDate }
            ?: next.currentDay
            ?: return next
        return reduceCascade(
            next,
            LookAfterIntent.RunCascadeReconciliation(
                day = day,
                now = intent.now,
                zone = intent.zone,
            ),
        )
    }

    private fun reduceMidnightSweep(
        current: LifeState,
        intent: LookAfterIntent.TriggerMidnightSweep,
    ): LifeState {
        // Universe for the reaper = active + parked (parked may still hold scheduledDate from yesterday).
        val universe = current.activeTasks + current.parkedQueue
        val result = DayScheduleReconciler.sweepDayBoundary(
            tasks = universe,
            previousDay = intent.previousDay,
            nextDay = intent.nextDay,
            now = intent.now,
            zone = intent.zone,
        )

        val resolvedById = result.tasks.associateBy { it.id }
        val mergedActive = current.activeTasks.map { resolvedById[it.id] ?: it }
        val mergedParked = current.parkedQueue.map { resolvedById[it.id] ?: it }

        // Tasks newly parked by the reaper leave active → parked.
        val newlyParkedIds = result.decisions
            .filter { it.action == ConflictCascadeAction.PARK }
            .map { it.taskId }
            .toSet()

        val stillActive = mergedActive.filterNot { it.id in newlyParkedIds }
        val promotedParked = mergedActive
            .filter { it.id in newlyParkedIds }
            .map {
                it.copy(
                    constraintType = ConstraintType.FLUID,
                    tags = (it.tags + "parked").distinct(),
                )
            }

        val logs = result.decisions.map { it.toActionLog(intent.now) }

        val afterTasks = current.copy(
            activeTasks = stillActive,
            parkedQueue = mergedParked + promotedParked,
            actionLogs = current.actionLogs + logs,
            currentDay = intent.nextDay,
        )
        // Daily medication taken-flags roll with the calendar day boundary (iOS parity).
        return reduceResetMedications(afterTasks, intent.nextDay)
    }

    private fun reduceCascade(
        current: LifeState,
        intent: LookAfterIntent.RunCascadeReconciliation,
    ): LifeState {
        val cascade = ConflictResolutionCascade.resolve(
            tasks = current.activeTasks,
            day = intent.day,
            now = intent.now,
            zone = intent.zone,
            bufferMinutes = intent.bufferMinutes,
        )

        val parkedIds = cascade.parkedTaskIds.toSet()
        val stillActive = cascade.tasks.filterNot { it.id in parkedIds }
        val newlyParked = cascade.tasks
            .filter { it.id in parkedIds }
            .map {
                it.copy(
                    constraintType = ConstraintType.FLUID,
                    tags = (it.tags + "parked").distinct(),
                )
            }

        val logs = cascade.decisions.map { it.toActionLog(intent.now) }

        return current.copy(
            activeTasks = stillActive,
            parkedQueue = current.parkedQueue + newlyParked,
            actionLogs = current.actionLogs + logs,
            currentDay = intent.day,
        )
    }

    // -------------------------------------------------------------------------
    // Medication reducers
    // -------------------------------------------------------------------------

    private fun reduceAddMedication(current: LifeState, medication: Medication): LifeState {
        val without = current.medications.filterNot { it.id == medication.id }
        return current.copy(medications = without + medication)
    }

    private fun reduceUpdateMedication(current: LifeState, medication: Medication): LifeState {
        val idx = current.medications.indexOfFirst { it.id == medication.id }
        return if (idx < 0) {
            reduceAddMedication(current, medication)
        } else {
            val next = current.medications.toMutableList()
            next[idx] = medication
            current.copy(medications = next)
        }
    }

    private fun reduceDeleteMedication(current: LifeState, id: String): LifeState =
        current.copy(medications = current.medications.filterNot { it.id == id })

    private fun reduceTakeMedication(
        current: LifeState,
        id: String,
        takenAt: Instant,
        taken: Boolean,
    ): LifeState {
        val idx = current.medications.indexOfFirst { it.id == id }
        if (idx < 0) return current
        val next = current.medications.toMutableList()
        next[idx] = if (taken) next[idx].markTaken(takenAt) else next[idx].markUntaken()
        return current.copy(medications = next)
    }

    private fun reduceResetMedications(current: LifeState, day: LocalDate): LifeState {
        if (current.medicationsLastResetDay == day) return current
        if (current.medications.isEmpty()) {
            return current.copy(medicationsLastResetDay = day)
        }
        val cleared = current.medications.map { it.copy(isTaken = false) }
        return current.copy(
            medications = cleared,
            medicationsLastResetDay = day,
        )
    }

    private fun stripTask(state: LifeState, id: String): LifeState = state.copy(
        activeTasks = state.activeTasks.filterNot { it.id == id },
        parkedQueue = state.parkedQueue.filterNot { it.id == id },
        somedayVault = state.somedayVault.filterNot { it.id == id },
    )

    private fun ConflictCascadeDecision.toActionLog(now: Instant): CascadeActionLog {
        val kind = when (action) {
            ConflictCascadeAction.KEEP -> CascadeActionKind.KEEP
            ConflictCascadeAction.SHIFT_LATER -> CascadeActionKind.SHIFTED_LATER
            ConflictCascadeAction.COMPRESS -> CascadeActionKind.COMPRESSED
            ConflictCascadeAction.DEFER_NEXT_GAP -> CascadeActionKind.DEFERRED
            ConflictCascadeAction.PARK -> CascadeActionKind.PARKED
            ConflictCascadeAction.EXPIRED -> CascadeActionKind.EXPIRED
            ConflictCascadeAction.SUPERSEDED -> CascadeActionKind.SUPERSEDED
        }
        return CascadeActionLog(
            id = UUID.randomUUID().toString(),
            taskId = taskId,
            action = kind,
            reason = reason,
            shiftMinutes = shiftMinutes ?: 0,
            recordedAt = now,
        )
    }
}
