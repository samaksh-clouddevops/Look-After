package com.lookafter.core.engine

import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.Medication
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

/**
 * User and system actions that [LifeEngine] can reduce into a new [LifeState].
 * Pure intent descriptors — no side effects.
 */
sealed interface LookAfterIntent {

    /** Insert or replace a task in the active pool. */
    data class AddTask(val task: LifeTask) : LookAfterIntent

    /** Remove a task from all buckets by id. */
    data class DeleteTask(val id: String) : LookAfterIntent {
        constructor(id: UUID) : this(id.toString())
    }

    /** Replace an existing task (matched by [LifeTask.id]) with an updated copy. */
    data class UpdateTask(val task: LifeTask) : LookAfterIntent

    /**
     * Apply manual board order: [orderedIds] get sortIndex 0..n-1 on matching
     * active tasks (Today drag-reorder).
     */
    data class ReorderTasks(val orderedIds: List<String>) : LookAfterIntent

    /** Week scrubber — sets the board's [LifeState.currentDay]. */
    data class SetCurrentDay(val day: LocalDate) : LookAfterIntent

    /** Move a task into the parked recovery queue and clear its clock. */
    data class ParkTask(val id: String, val reason: String = "manual_park") : LookAfterIntent

    /** Move a task into the someday vault. */
    data class MoveToSomeday(val id: String) : LookAfterIntent

    /** Resurrect a parked task back into the active pool. */
    data class UnparkTask(val id: String) : LookAfterIntent

    /** Mark a task completed (timeline completion control). */
    data class CompleteTask(
        val id: String,
        val completedAt: Instant = Instant.now(),
    ) : LookAfterIntent

    /**
     * Commit what-if tasks from [com.lookafter.core.simulation.SimulationEngine]
     * into the live universe and re-run cascade for [day].
     */
    data class CommitHypotheticalTasks(
        val tasks: List<LifeTask>,
        val day: LocalDate? = null,
        val now: Instant = Instant.now(),
        val zone: ZoneId = ZoneId.of("UTC"),
    ) : LookAfterIntent

    /**
     * Midnight / day-boundary Reaper sweep.
     * Rolls [previousDay] incompletes against [nextDay] actives via
     * [com.lookafter.core.planning.DayScheduleReconciler.sweepDayBoundary].
     */
    data class TriggerMidnightSweep(
        val previousDay: LocalDate,
        val nextDay: LocalDate,
        val now: Instant = Instant.now(),
        val zone: ZoneId = ZoneId.of("UTC"),
    ) : LookAfterIntent

    /**
     * Run the conflict cascade over active tasks on [day].
     * Emits a new state with resolved tasks + cascade action logs.
     */
    data class RunCascadeReconciliation(
        val day: LocalDate,
        val now: Instant = Instant.now(),
        val zone: ZoneId = ZoneId.of("UTC"),
        val bufferMinutes: Int = 5,
    ) : LookAfterIntent

    /** Replace the entire universe (hydrate / factory reset). */
    data class ReplaceState(val state: LifeState) : LookAfterIntent

    /** Update the consecutive high-load day counter. */
    data class SetHighLoadStreak(val days: Int) : LookAfterIntent

    // -- Medication domain (mirrors iOS LookAfterIntent) ---------------------

    data class AddMedication(val medication: Medication) : LookAfterIntent

    data class UpdateMedication(val medication: Medication) : LookAfterIntent

    data class DeleteMedication(val id: String) : LookAfterIntent

    /** Mark a dose taken (or untaken when [taken] is false). */
    data class TakeMedication(
        val id: String,
        val takenAt: Instant = Instant.now(),
        val taken: Boolean = true,
    ) : LookAfterIntent

    /** Clear daily `isTaken` flags when the calendar day advances. */
    data class ResetMedicationsForNewDay(val day: LocalDate) : LookAfterIntent

    /** Bulk replace inventory (migration / planning applier). */
    data class ReplaceMedications(val medications: List<Medication>) : LookAfterIntent
}
