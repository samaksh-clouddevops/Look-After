package com.lookafter.core.engine

import com.lookafter.core.models.CascadeActionLog
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.Medication
import com.lookafter.core.models.Priority
import com.lookafter.core.models.TaskStatus
import com.lookafter.core.serialization.LocalDateSerializer
import java.time.LocalDate
import kotlinx.serialization.Serializable

/**
 * Immutable single source of truth for the Look After operational universe.
 *
 * Pure data — no IO, no Android. Engines reduce intents into a new [LifeState]
 * via [copy]; never mutate in place. Mirrors iOS `LifeState`.
 */
@Serializable
data class LifeState(
    val activeTasks: List<LifeTask> = emptyList(),
    val parkedQueue: List<LifeTask> = emptyList(),
    val somedayVault: List<LifeTask> = emptyList(),
    val actionLogs: List<CascadeActionLog> = emptyList(),
    val consecutiveHighLoadDays: Int = 0,
    /** Calendar day the engine last treated as "today" (for midnight sweeps). */
    @Serializable(with = LocalDateSerializer::class)
    val currentDay: LocalDate? = null,
    /** Medication inventory / daily schedule owned by the UDF pipeline. */
    val medications: List<Medication> = emptyList(),
    /** Start-of-day when medication `isTaken` flags were last cleared. */
    @Serializable(with = LocalDateSerializer::class)
    val medicationsLastResetDay: LocalDate? = null,
) {
    fun taskById(id: String): LifeTask? =
        activeTasks.firstOrNull { it.id == id }
            ?: parkedQueue.firstOrNull { it.id == id }
            ?: somedayVault.firstOrNull { it.id == id }

    fun medicationById(id: String): Medication? =
        medications.firstOrNull { it.id == id }

    /** Today's adherence rate across configured medications (0…1). */
    val medicationAdherenceRate: Double
        get() {
            if (medications.isEmpty()) return 0.0
            val taken = medications.count { it.isTaken }
            return taken.toDouble() / medications.size.toDouble()
        }

    fun withActiveTasks(tasks: List<LifeTask>): LifeState = copy(activeTasks = tasks)

    fun appendLogs(logs: List<CascadeActionLog>): LifeState =
        if (logs.isEmpty()) this else copy(actionLogs = actionLogs + logs)

    companion object {
        val EMPTY: LifeState = LifeState()
    }
}

/**
 * Partition a flat task list into the three operational buckets.
 * Used when hydrating [LifeState] from storage snapshots.
 */
fun LifeState.Companion.fromTasks(
    tasks: List<LifeTask>,
    actionLogs: List<CascadeActionLog> = emptyList(),
    consecutiveHighLoadDays: Int = 0,
    currentDay: LocalDate? = null,
): LifeState {
    val active = mutableListOf<LifeTask>()
    val parked = mutableListOf<LifeTask>()
    val someday = mutableListOf<LifeTask>()
    for (task in tasks) {
        when {
            task.priority == Priority.SOMEDAY && task.status.isActive -> someday += task
            task.status == TaskStatus.DEFERRED ||
                (task.status.isActive && task.scheduledDate == null && task.constraintType.name == "FLUID" &&
                    task.tags.any { it.contains("park") || it == "parked" }) -> parked += task
            task.status.isActive ||
                task.status == TaskStatus.COMPLETED ||
                task.status == TaskStatus.EXPIRED ||
                task.status == TaskStatus.SUPERSEDED ||
                task.status == TaskStatus.SKIPPED -> active += task
            else -> active += task
        }
    }
    return LifeState(
        activeTasks = active,
        parkedQueue = parked,
        somedayVault = someday,
        actionLogs = actionLogs,
        consecutiveHighLoadDays = consecutiveHighLoadDays,
        currentDay = currentDay,
    )
}
