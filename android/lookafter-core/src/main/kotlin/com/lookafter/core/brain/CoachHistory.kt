package com.lookafter.core.brain

import com.lookafter.core.serialization.InstantSerializer
import java.time.Instant
import java.util.UUID
import kotlinx.serialization.Serializable

@Serializable
enum class CoachHistoryKind {
    HERO_DECISION,
    COACH_REPLY,
    PLAN_ACCEPTED,
    PLAN_DISCARDED,
    NOTE,
}

/**
 * A single coach-history entry — pinned decisions and "why this hero" moments
 * survive chat clear (Phase B4).
 */
@Serializable
data class CoachHistoryEntry(
    val id: String = UUID.randomUUID().toString(),
    val kind: CoachHistoryKind = CoachHistoryKind.NOTE,
    val title: String = "",
    val body: String = "",
    val heroTaskId: String? = null,
    val pinned: Boolean = false,
    @Serializable(with = InstantSerializer::class)
    val at: Instant = Instant.EPOCH,
)

@Serializable
data class CoachHistoryState(
    val entries: List<CoachHistoryEntry> = emptyList(),
) {
    val pinned: List<CoachHistoryEntry>
        get() = entries.filter { it.pinned }.sortedByDescending { it.at }

    val recent: List<CoachHistoryEntry>
        get() = entries.sortedByDescending { it.at }

    companion object {
        val EMPTY = CoachHistoryState()
        const val MAX_ENTRIES = 80
        const val MAX_PINNED = 12
    }
}

sealed class CoachHistoryIntent {
    data class Record(val entry: CoachHistoryEntry) : CoachHistoryIntent()
    data class Pin(val id: String, val pinned: Boolean = true) : CoachHistoryIntent()
    data class Remove(val id: String) : CoachHistoryIntent()
    data object ClearUnpinned : CoachHistoryIntent()
    data object ClearAll : CoachHistoryIntent()
}

object CoachHistoryEngine {

    fun reduce(current: CoachHistoryState, intent: CoachHistoryIntent): CoachHistoryState =
        when (intent) {
            is CoachHistoryIntent.Record -> {
                val next = listOf(intent.entry) + current.entries
                compact(CoachHistoryState(entries = next))
            }
            is CoachHistoryIntent.Pin -> {
                var pinCount = current.entries.count { it.pinned && it.id != intent.id }
                val entries = current.entries.map { e ->
                    if (e.id != intent.id) return@map e
                    if (intent.pinned && pinCount >= CoachHistoryState.MAX_PINNED) e
                    else {
                        if (intent.pinned) pinCount++
                        e.copy(pinned = intent.pinned)
                    }
                }
                current.copy(entries = entries)
            }
            is CoachHistoryIntent.Remove ->
                current.copy(entries = current.entries.filterNot { it.id == intent.id })
            CoachHistoryIntent.ClearUnpinned ->
                current.copy(entries = current.entries.filter { it.pinned })
            CoachHistoryIntent.ClearAll -> CoachHistoryState.EMPTY
        }

    /** Snapshot hero decision into history (idempotent within same tick title+reason). */
    fun fromHeroDecision(
        decision: BrainDecision,
        world: WorldState = WorldState.EMPTY,
        now: Instant = Instant.now(),
    ): CoachHistoryEntry = CoachHistoryEntry(
        kind = CoachHistoryKind.HERO_DECISION,
        title = decision.heroTitle.ifBlank { "No hero" },
        body = buildString {
            append(decision.reason.ifBlank { "Protect the quiet." })
            if (decision.coachLine.isNotBlank()) {
                append("\n")
                append(decision.coachLine)
            }
            append("\n")
            append(
                "Capacity ${world.capacityBand.label} · load ${world.cognitiveLoad.name.lowercase()}",
            )
        },
        heroTaskId = decision.heroTaskId,
        at = now,
    )

    fun fromCoachReply(text: String, now: Instant = Instant.now()): CoachHistoryEntry =
        CoachHistoryEntry(
            kind = CoachHistoryKind.COACH_REPLY,
            title = "Coach",
            body = text.trim().take(500),
            at = now,
        )

    fun fromPlanOutcome(
        accepted: Boolean,
        summary: String,
        mutationCount: Int,
        now: Instant = Instant.now(),
    ): CoachHistoryEntry = CoachHistoryEntry(
        kind = if (accepted) CoachHistoryKind.PLAN_ACCEPTED else CoachHistoryKind.PLAN_DISCARDED,
        title = if (accepted) "Plan accepted" else "Plan discarded",
        body = buildString {
            append(summary.ifBlank { "Plan" })
            if (mutationCount > 0) append(" · $mutationCount change(s)")
        },
        at = now,
    )

    private fun compact(state: CoachHistoryState): CoachHistoryState {
        val pinned = state.entries.filter { it.pinned }.take(CoachHistoryState.MAX_PINNED)
        val unpinned = state.entries.filterNot { it.pinned }
            .sortedByDescending { it.at }
            .take(CoachHistoryState.MAX_ENTRIES - pinned.size)
        return state.copy(
            entries = (pinned + unpinned).sortedByDescending { it.at },
        )
    }
}
