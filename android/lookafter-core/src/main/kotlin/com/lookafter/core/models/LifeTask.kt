package com.lookafter.core.models

import com.lookafter.core.serialization.InstantSerializer
import com.lookafter.core.serialization.LocalDateSerializer
import java.time.Instant
import java.time.LocalDate
import java.util.UUID
import kotlinx.serialization.Serializable

/**
 * A task in the Look After physics engine.
 *
 * Phase-1 physics surface: identity, duration, constraint, status, semantic
 * collision key, expiration, and temporal bounds. Immutable — use [copy].
 *
 * Mirrors the scheduling-relevant fields of iOS `LifeTask`.
 */
@Serializable
data class LifeTask(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val durationMinutes: Int = 30,
    val constraintType: ConstraintType = ConstraintType.FLEXIBLE,
    val status: TaskStatus = TaskStatus.PENDING,
    /** Semantic collision key (hash). Same key + DropOldest → supersede on rollover. */
    val semanticHash: String = "",
    val expirationPolicy: TaskExpirationPolicy = TaskExpirationPolicy.Infinite,
    val collisionStrategy: SemanticCollisionStrategy = SemanticCollisionStrategy.ALLOW_MULTIPLE,
    val temporalBoundingBox: TemporalBoundingBox? = null,
    @Serializable(with = LocalDateSerializer::class)
    val scheduledDate: LocalDate? = null,
    @Serializable(with = InstantSerializer::class)
    val scheduledStart: Instant? = null,
    @Serializable(with = InstantSerializer::class)
    val scheduledEnd: Instant? = null,
    val minimumViableDurationMinutes: Int = DEFAULT_MINIMUM_MINUTES,
    val priority: Priority = Priority.MEDIUM,
    val recurrence: RecurrenceRule = RecurrenceRule.NONE,
    /** Optional freeform notes (description). */
    val notes: String = "",
    val tags: List<String> = emptyList(),
    val parentTaskId: String? = null,
    @Serializable(with = InstantSerializer::class)
    val createdAt: Instant = Instant.EPOCH,
    @Serializable(with = InstantSerializer::class)
    val updatedAt: Instant = Instant.EPOCH,
    @Serializable(with = InstantSerializer::class)
    val completedAt: Instant? = null,
) {
    val isCompleted: Boolean get() = status == TaskStatus.COMPLETED

    val isLifeCommitment: Boolean
        get() = tags.any { it == LIFE_COMMITMENT_TAG || it.startsWith("commitment:") }

    fun withConstraint(type: ConstraintType): LifeTask = copy(constraintType = type)

    fun clearedSchedule(now: Instant = Instant.now()): LifeTask = copy(
        scheduledStart = null,
        scheduledEnd = null,
        updatedAt = now,
    )

    companion object {
        const val DEFAULT_MINIMUM_MINUTES: Int = 15
        const val LIFE_COMMITMENT_TAG: String = "life-commitment"
    }
}
