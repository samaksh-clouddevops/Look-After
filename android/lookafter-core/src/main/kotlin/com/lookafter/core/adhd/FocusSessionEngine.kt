package com.lookafter.core.adhd

import com.lookafter.core.serialization.InstantSerializer
import java.time.Duration
import java.time.Instant
import kotlinx.serialization.Serializable

@Serializable
enum class FocusSessionPhase { IDLE, RUNNING, PAUSED, COMPLETED, ABORTED }

/**
 * Pure ADHD / deep-work focus session state machine.
 * UI drives intents; this owns timing math only.
 */
@Serializable
data class FocusSessionState(
    val phase: FocusSessionPhase = FocusSessionPhase.IDLE,
    val taskId: String? = null,
    val taskTitle: String = "",
    val plannedMinutes: Int = 25,
    @Serializable(with = InstantSerializer::class)
    val startedAt: Instant? = null,
    @Serializable(with = InstantSerializer::class)
    val pausedAt: Instant? = null,
    /** Accumulated active work while previously running (excludes current run segment). */
    val accumulatedActiveSeconds: Long = 0,
    val emergencyMode: Boolean = false,
) {
    fun remainingSeconds(now: Instant = Instant.now()): Long {
        val total = plannedMinutes * 60L
        val used = elapsedActiveSeconds(now)
        return (total - used).coerceAtLeast(0)
    }

    fun elapsedActiveSeconds(now: Instant = Instant.now()): Long {
        val base = accumulatedActiveSeconds
        return when (phase) {
            FocusSessionPhase.RUNNING -> {
                val start = startedAt ?: return base
                base + Duration.between(start, now).seconds.coerceAtLeast(0)
            }
            else -> base
        }
    }

    val progress: Float
        get() {
            val total = (plannedMinutes * 60).toFloat().coerceAtLeast(1f)
            return (elapsedActiveSeconds().toFloat() / total).coerceIn(0f, 1f)
        }
}

sealed class FocusSessionIntent {
    data class Start(
        val taskId: String?,
        val taskTitle: String,
        val plannedMinutes: Int = 25,
        val emergencyMode: Boolean = false,
        val now: Instant = Instant.now(),
    ) : FocusSessionIntent()

    data class Pause(val now: Instant = Instant.now()) : FocusSessionIntent()
    data class Resume(val now: Instant = Instant.now()) : FocusSessionIntent()
    data class Complete(val now: Instant = Instant.now()) : FocusSessionIntent()
    data class Abort(val now: Instant = Instant.now()) : FocusSessionIntent()
    data class Tick(val now: Instant = Instant.now()) : FocusSessionIntent()
}

object FocusSessionEngine {
    fun reduce(current: FocusSessionState, intent: FocusSessionIntent): FocusSessionState =
        when (intent) {
            is FocusSessionIntent.Start -> FocusSessionState(
                phase = FocusSessionPhase.RUNNING,
                taskId = intent.taskId,
                taskTitle = intent.taskTitle,
                // Allow short blocks (tests / emergency) down to 1 minute.
                plannedMinutes = intent.plannedMinutes.coerceIn(1, 180),
                startedAt = intent.now,
                emergencyMode = intent.emergencyMode,
            )
            is FocusSessionIntent.Pause -> {
                if (current.phase != FocusSessionPhase.RUNNING) current
                else {
                    val elapsed = current.elapsedActiveSeconds(intent.now)
                    current.copy(
                        phase = FocusSessionPhase.PAUSED,
                        pausedAt = intent.now,
                        accumulatedActiveSeconds = elapsed,
                        startedAt = null,
                    )
                }
            }
            is FocusSessionIntent.Resume -> {
                if (current.phase != FocusSessionPhase.PAUSED) current
                else current.copy(
                    phase = FocusSessionPhase.RUNNING,
                    startedAt = intent.now,
                    pausedAt = null,
                )
            }
            is FocusSessionIntent.Complete -> current.copy(
                phase = FocusSessionPhase.COMPLETED,
                accumulatedActiveSeconds = current.elapsedActiveSeconds(intent.now),
                startedAt = null,
                pausedAt = null,
            )
            is FocusSessionIntent.Abort -> current.copy(
                phase = FocusSessionPhase.ABORTED,
                accumulatedActiveSeconds = current.elapsedActiveSeconds(intent.now),
                startedAt = null,
                pausedAt = null,
            )
            is FocusSessionIntent.Tick -> {
                if (current.phase == FocusSessionPhase.RUNNING &&
                    current.remainingSeconds(intent.now) <= 0
                ) {
                    current.copy(
                        phase = FocusSessionPhase.COMPLETED,
                        accumulatedActiveSeconds = current.plannedMinutes * 60L,
                        startedAt = null,
                    )
                } else {
                    current
                }
            }
        }
}
