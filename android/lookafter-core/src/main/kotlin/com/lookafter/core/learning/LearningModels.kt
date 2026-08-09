package com.lookafter.core.learning

import com.lookafter.core.serialization.InstantSerializer
import com.lookafter.core.serialization.LocalDateSerializer
import java.time.Instant
import java.time.LocalDate
import java.util.UUID
import kotlinx.serialization.Serializable

@Serializable
enum class ReviewGrade {
    AGAIN,
    HARD,
    GOOD,
    EASY,
}

@Serializable
data class LearningCard(
    val id: String = UUID.randomUUID().toString(),
    val front: String,
    val back: String = "",
    val tags: List<String> = emptyList(),
    /** Spaced interval in days until next review. */
    val intervalDays: Int = 0,
    val easeFactor: Double = 2.5,
    val repetitions: Int = 0,
    @Serializable(with = LocalDateSerializer::class)
    val dueOn: LocalDate = LocalDate.now(),
    @Serializable(with = InstantSerializer::class)
    val lastReviewedAt: Instant? = null,
    @Serializable(with = InstantSerializer::class)
    val createdAt: Instant = Instant.EPOCH,
)

@Serializable
data class LearningTrack(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val subtitle: String = "",
    val cardIds: List<String> = emptyList(),
    @Serializable(with = InstantSerializer::class)
    val createdAt: Instant = Instant.EPOCH,
) {
    val cardCount: Int get() = cardIds.size
}

@Serializable
data class LearningState(
    val tracks: List<LearningTrack> = emptyList(),
    val cards: List<LearningCard> = emptyList(),
    val selectedTrackId: String? = null,
) {
    val selectedTrack: LearningTrack?
        get() = tracks.firstOrNull { it.id == selectedTrackId } ?: tracks.firstOrNull()

    fun cardsForTrack(trackId: String): List<LearningCard> {
        val track = tracks.firstOrNull { it.id == trackId } ?: return emptyList()
        val byId = cards.associateBy { it.id }
        return track.cardIds.mapNotNull { byId[it] }
    }

    fun dueCards(today: LocalDate = LocalDate.now(), trackId: String? = selectedTrackId): List<LearningCard> {
        val pool = if (trackId != null) cardsForTrack(trackId) else cards
        return pool.filter { !it.dueOn.isAfter(today) }
            .sortedWith(compareBy({ it.dueOn }, { it.front.lowercase() }))
    }

    val dueCount: Int get() = dueCards().size

    companion object {
        val EMPTY = LearningState()
    }
}

sealed class LearningIntent {
    data class AddTrack(val track: LearningTrack) : LearningIntent()
    data class DeleteTrack(val id: String) : LearningIntent()
    data class SelectTrack(val id: String?) : LearningIntent()
    data class AddCard(val card: LearningCard, val trackId: String? = null) : LearningIntent()
    data class DeleteCard(val id: String) : LearningIntent()
    data class ReviewCard(
        val cardId: String,
        val grade: ReviewGrade,
        val today: LocalDate = LocalDate.now(),
        val now: Instant = Instant.now(),
    ) : LearningIntent()
    data class ReplaceState(val state: LearningState) : LearningIntent()
}

/**
 * Lightweight spaced practice (SM-2–inspired ladder) — Phase E3.
 * Intervals: Again→0/1d, Hard slow climb, Good/Easy stretch.
 */
object LearningEngine {

    fun reduce(current: LearningState, intent: LearningIntent): LearningState = when (intent) {
        is LearningIntent.AddTrack -> {
            val track = normalizeTrack(intent.track)
            current.copy(
                tracks = listOf(track) + current.tracks,
                selectedTrackId = track.id,
            )
        }
        is LearningIntent.DeleteTrack -> current.copy(
            tracks = current.tracks.filterNot { it.id == intent.id },
            // keep cards orphaned (can still be due globally) or strip refs
            selectedTrackId = current.selectedTrackId?.takeIf { it != intent.id },
        )
        is LearningIntent.SelectTrack -> current.copy(selectedTrackId = intent.id)
        is LearningIntent.AddCard -> {
            val card = normalizeCard(intent.card)
            var tracks = current.tracks
            val trackId = intent.trackId ?: current.selectedTrackId
            if (trackId != null) {
                tracks = tracks.map { t ->
                    if (t.id == trackId && card.id !in t.cardIds) {
                        t.copy(cardIds = listOf(card.id) + t.cardIds)
                    } else t
                }
            }
            current.copy(cards = listOf(card) + current.cards, tracks = tracks)
        }
        is LearningIntent.DeleteCard -> current.copy(
            cards = current.cards.filterNot { it.id == intent.id },
            tracks = current.tracks.map { t -> t.copy(cardIds = t.cardIds.filterNot { it == intent.id }) },
        )
        is LearningIntent.ReviewCard -> {
            val updated = current.cards.map { c ->
                if (c.id != intent.cardId) c
                else applyReview(c, intent.grade, intent.today, intent.now)
            }
            current.copy(cards = updated)
        }
        is LearningIntent.ReplaceState -> intent.state
    }

    fun applyReview(
        card: LearningCard,
        grade: ReviewGrade,
        today: LocalDate = LocalDate.now(),
        now: Instant = Instant.now(),
    ): LearningCard {
        var ease = card.easeFactor
        var reps = card.repetitions
        var interval = card.intervalDays
        when (grade) {
            ReviewGrade.AGAIN -> {
                reps = 0
                interval = 0
                ease = (ease - 0.2).coerceAtLeast(1.3)
            }
            ReviewGrade.HARD -> {
                reps += 1
                ease = (ease - 0.15).coerceAtLeast(1.3)
                interval = when {
                    interval <= 0 -> 1
                    else -> (interval * 1.2).toInt().coerceAtLeast(1)
                }
            }
            ReviewGrade.GOOD -> {
                reps += 1
                interval = when {
                    reps == 1 -> 1
                    reps == 2 -> 3
                    else -> (interval * ease).toInt().coerceAtLeast(interval + 1)
                }
            }
            ReviewGrade.EASY -> {
                reps += 1
                ease = (ease + 0.15).coerceAtMost(3.0)
                interval = when {
                    reps == 1 -> 2
                    reps == 2 -> 5
                    else -> (interval * ease * 1.3).toInt().coerceAtLeast(interval + 2)
                }
            }
        }
        return card.copy(
            intervalDays = interval.coerceIn(0, 365),
            easeFactor = (ease * 100).toInt() / 100.0,
            repetitions = reps,
            dueOn = today.plusDays(interval.toLong().coerceAtLeast(if (grade == ReviewGrade.AGAIN) 0 else 1)),
            lastReviewedAt = now,
        )
    }

    fun defaultTrack(now: Instant = Instant.now()): LearningTrack =
        LearningTrack(title = "General", subtitle = "Light practice queue", createdAt = now)

    private fun normalizeTrack(t: LearningTrack): LearningTrack =
        t.copy(title = t.title.trim().ifBlank { "Track" }, subtitle = t.subtitle.trim())

    private fun normalizeCard(c: LearningCard): LearningCard {
        val now = Instant.now()
        return c.copy(
            front = c.front.trim().ifBlank { "Card" },
            back = c.back.trim(),
            tags = c.tags.map { it.trim() }.filter { it.isNotEmpty() }.distinct(),
            createdAt = if (c.createdAt.epochSecond <= 0) now else c.createdAt,
            dueOn = c.dueOn,
        )
    }
}
