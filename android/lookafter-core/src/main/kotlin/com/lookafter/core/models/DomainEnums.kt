package com.lookafter.core.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * How tightly a timeline block is locked to its scheduled slot.
 * Mirrors iOS `TimeConstraint` (anchored / flexible / fluid).
 */
@Serializable
enum class ConstraintType {
    /** Immovable — meetings, fixed commitments. */
    ANCHORED,

    /** Preferred slot — cascade may reorder within bounds. */
    FLEXIBLE,

    /** Soft intent — freely movable; lowest rank. */
    FLUID,
}

/**
 * Lifecycle status of a [LifeTask].
 * Mirrors iOS `TaskStatus`.
 */
@Serializable
enum class TaskStatus {
    PENDING,
    IN_PROGRESS,
    PAUSED,
    COMPLETED,
    SKIPPED,
    DEFERRED,

    /** Ephemeral window missed — contextual kill, not a failure. */
    EXPIRED,

    /** Semantic collision dropped this instance (duplicate already on the day). */
    SUPERSEDED,
    ;

    /** True when the task still competes for schedule real-estate. */
    val isActive: Boolean
        get() = this == PENDING || this == IN_PROGRESS || this == PAUSED
}

/**
 * How rollovers interact with an existing same-hash instance on the destination day.
 * Mirrors iOS `SemanticCollisionStrategy`.
 */
@Serializable
enum class SemanticCollisionStrategy {
    /** Allow multiple instances (e.g. "Read 10 pages"). */
    ALLOW_MULTIPLE,

    /** Drop the older incomplete if today already has this activity. */
    DROP_OLDEST,

    /** Prefer the old incomplete; block the newer scheduled instance. */
    BLOCK_NEWEST,
}

/**
 * When an incomplete task dies instead of parking / rolling forever.
 * Mirrors iOS `TaskExpirationPolicy`.
 */
@Serializable
sealed class TaskExpirationPolicy {
    /** Survives multi-day rollover (subject to collision + horizon). */
    @Serializable
    @SerialName("Infinite")
    data object Infinite : TaskExpirationPolicy()

    /** Dies at local midnight if not completed — never rolls. */
    @Serializable
    @SerialName("EndOfDay")
    data object EndOfDay : TaskExpirationPolicy()

    /** Dies if not started within [minutes] of scheduled start. */
    @Serializable
    @SerialName("StrictWindow")
    data class StrictWindow(val minutes: Int) : TaskExpirationPolicy()

    companion object {
        val DEFAULT: TaskExpirationPolicy = Infinite
    }
}

/**
 * Outcome applied to a single task during conflict auto-triage.
 * Mirrors iOS `ConflictCascadeAction`.
 */
@Serializable
enum class ConflictCascadeAction {
    KEEP,
    SHIFT_LATER,
    COMPRESS,
    DEFER_NEXT_GAP,
    PARK,
    EXPIRED,
    SUPERSEDED,
}

/**
 * Workspace category for execution surfaces.
 * Mirrors iOS `FocusTaskCategory`.
 */
@Serializable
enum class FocusTaskCategory {
    DEEP_WORK,
    RECOVERY,
    ADMIN,
    HEALTH,
    CREATIVE,
    SOCIAL,
    FLUID_GAP,
}

/**
 * Visual / behavioral mode for Live Activity and Focus surfaces.
 * Mirrors iOS `ExecutionSurfaceMode`.
 */
@Serializable
enum class ExecutionSurfaceMode {
    ANCHORED,
    FLEXIBLE,
    RECOVERY,
    FLUID_GAP,
    IDLE,
}

/**
 * Priority level used by cascade ranking.
 * Mirrors iOS `Priority`.
 */
@Serializable
enum class Priority(val rankBonus: Int) {
    CRITICAL(10),
    HIGH(8),
    MEDIUM(4),
    LOW(2),
    SOMEDAY(0),
}
