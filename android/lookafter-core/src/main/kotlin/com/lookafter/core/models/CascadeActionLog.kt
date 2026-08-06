package com.lookafter.core.models

import java.time.Instant
import java.util.UUID

/**
 * Historical cascade / reaper action recorded for briefing + weekly review.
 * Immutable event — pure data, no persistence side effects.
 *
 * Phase-1 surface intentionally rich enough for [com.lookafter.core.planning.WeeklyReviewAggregator].
 */
data class CascadeActionLog(
    val id: String = UUID.randomUUID().toString(),
    val taskId: String? = null,
    val action: CascadeActionKind,
    val reason: String = "",
    /** Minutes of focus work preserved/completed associated with this action (if any). */
    val focusMinutes: Int = 0,
    /** Minutes reclaimed (e.g. sabotage auction recovery block enforcement). */
    val reclaimedMinutes: Int = 0,
    /** Minutes a block was shifted later (Stage 1 cascade). */
    val shiftMinutes: Int = 0,
    val recordedAt: Instant = Instant.now(),
)

/**
 * Macro kinds the weekly aggregator and cascade distiller understand.
 */
enum class CascadeActionKind {
    /** Recovery / sabotage lock enforced — time reclaimed for rest. */
    SABOTAGE_AUCTION,

    /** Task was shifted later same day. */
    SHIFTED_LATER,

    /** Semantic collision dropped a duplicate / stale instance. */
    SUPERSEDED,

    /** Ephemeral window missed. */
    EXPIRED,

    /** Task parked into recovery queue. */
    PARKED,

    /** Duration compressed to viable floor. */
    COMPRESSED,

    /** Deferred into a later open gap. */
    DEFERRED,

    /** Focus block completed / kept — contributes to focus hours. */
    FOCUS_COMPLETED,

    /** Generic keep / no-op bookkeeping. */
    KEEP,
}

/**
 * Single per-task decision emitted by [com.lookafter.core.planning.ConflictResolutionCascade].
 * Mirrors iOS `ConflictCascadeDecision`.
 */
data class ConflictCascadeDecision(
    val taskId: String,
    val action: ConflictCascadeAction,
    val reason: String,
    val shiftMinutes: Int? = null,
    val compressHitViableFloor: Boolean? = null,
    val compressDeltaMinutes: Int? = null,
)

/**
 * Result of a cascade resolve pass.
 * Mirrors iOS `ConflictCascadeResult`.
 */
data class ConflictCascadeResult(
    val tasks: List<LifeTask>,
    val decisions: List<ConflictCascadeDecision> = emptyList(),
    val changedTaskIds: Set<String> = emptySet(),
    val unresolvedTaskIds: Set<String> = emptySet(),
    val parkedTaskIds: List<String> = emptyList(),
    val triggeredRecoveryLock: Boolean = false,
)

/**
 * Result of day boundary / reconcile passes.
 * Mirrors iOS `DayScheduleReconciler.Result`.
 */
data class DayReconcileResult(
    val tasks: List<LifeTask>,
    val changedTaskIds: Set<String> = emptySet(),
    val conflictTaskIds: Set<String> = emptySet(),
    val decisions: List<ConflictCascadeDecision> = emptyList(),
)
