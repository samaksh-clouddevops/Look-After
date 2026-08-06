package com.lookafter.core.models

import java.time.Duration
import java.time.Instant
import java.util.UUID
import kotlin.math.max
import kotlin.math.min

/**
 * Immutable projection of the currently active execution block.
 * Produced by execution resolvers — UI only consumes this.
 * Mirrors iOS `ExecutionBlockSnapshot`.
 */
data class ExecutionBlockSnapshot(
    val id: String = UUID.randomUUID().toString(),
    val taskId: String? = null,
    val taskTitle: String,
    val category: FocusTaskCategory,
    val surfaceMode: ExecutionSurfaceMode,
    val constraintType: ConstraintType? = null,
    val windowStart: Instant,
    val windowEnd: Instant,
    val progressFraction: Double,
    val nextUpSummary: String = "",
    val confidence: Double = 1.0,
    val generatedAt: Instant = Instant.now(),
) {
    val remainingSeconds: Long
        get() = max(0L, Duration.between(generatedAt, windowEnd).seconds)

    val isFocusEligible: Boolean
        get() = when (surfaceMode) {
            ExecutionSurfaceMode.ANCHORED, ExecutionSurfaceMode.FLEXIBLE -> true
            ExecutionSurfaceMode.RECOVERY,
            ExecutionSurfaceMode.FLUID_GAP,
            ExecutionSurfaceMode.IDLE,
            -> false
        }

    val constraintLabel: String
        get() = when (surfaceMode) {
            ExecutionSurfaceMode.ANCHORED -> "Anchored"
            ExecutionSurfaceMode.FLEXIBLE -> "Flexible"
            ExecutionSurfaceMode.RECOVERY -> "Recovery"
            ExecutionSurfaceMode.FLUID_GAP -> "Fluid"
            ExecutionSurfaceMode.IDLE -> "Idle"
        }

    companion object {
        val IDLE: ExecutionBlockSnapshot = ExecutionBlockSnapshot(
            id = "idle",
            taskTitle = "",
            category = FocusTaskCategory.FLUID_GAP,
            surfaceMode = ExecutionSurfaceMode.IDLE,
            windowStart = Instant.EPOCH,
            windowEnd = Instant.EPOCH,
            progressFraction = 0.0,
            confidence = 0.0,
            generatedAt = Instant.EPOCH,
        )

        fun clamped(
            id: String = UUID.randomUUID().toString(),
            taskId: String? = null,
            taskTitle: String,
            category: FocusTaskCategory,
            surfaceMode: ExecutionSurfaceMode,
            constraintType: ConstraintType? = null,
            windowStart: Instant,
            windowEnd: Instant,
            progressFraction: Double,
            nextUpSummary: String = "",
            confidence: Double = 1.0,
            generatedAt: Instant = Instant.now(),
        ): ExecutionBlockSnapshot = ExecutionBlockSnapshot(
            id = id,
            taskId = taskId,
            taskTitle = taskTitle,
            category = category,
            surfaceMode = surfaceMode,
            constraintType = constraintType,
            windowStart = windowStart,
            windowEnd = windowEnd,
            progressFraction = min(1.0, max(0.0, progressFraction)),
            nextUpSummary = nextUpSummary,
            confidence = min(1.0, max(0.0, confidence)),
            generatedAt = generatedAt,
        )
    }
}
