package com.lookafter.core.inbox

import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.TaskExpirationPolicy
import com.lookafter.core.models.TaskStatus
import com.lookafter.core.serialization.InstantSerializer
import java.time.Instant
import java.time.LocalDate
import java.util.UUID
import kotlinx.serialization.Serializable

/**
 * Unprocessed capture — mirrors iOS inbox rows before scheduling.
 */
@Serializable
data class InboxItem(
    val id: String = UUID.randomUUID().toString(),
    val text: String,
    @Serializable(with = InstantSerializer::class)
    val createdAt: Instant = Instant.now(),
    val processed: Boolean = false,
)

@Serializable
data class InboxState(
    val items: List<InboxItem> = emptyList(),
) {
    val open: List<InboxItem> get() = items.filter { !it.processed }
}

sealed class InboxIntent {
    data class Capture(val text: String, val now: Instant = Instant.now()) : InboxIntent()
    data class Discard(val id: String) : InboxIntent()
    data class MarkProcessed(val id: String) : InboxIntent()
    data class PromoteToTask(
        val id: String,
        val durationMinutes: Int = 15,
        val day: LocalDate = LocalDate.now(),
    ) : InboxIntent()
}

data class InboxReduceResult(
    val state: InboxState,
    /** Task to dispatch via LifeEngine when promoting. */
    val spawnedTask: LifeTask? = null,
)

object InboxEngine {
    fun reduce(current: InboxState, intent: InboxIntent): InboxReduceResult = when (intent) {
        is InboxIntent.Capture -> {
            val text = intent.text.trim()
            if (text.isEmpty()) InboxReduceResult(current)
            else InboxReduceResult(
                current.copy(
                    items = listOf(
                        InboxItem(text = text, createdAt = intent.now),
                    ) + current.items,
                ),
            )
        }
        is InboxIntent.Discard -> InboxReduceResult(
            current.copy(items = current.items.filterNot { it.id == intent.id }),
        )
        is InboxIntent.MarkProcessed -> InboxReduceResult(
            current.copy(
                items = current.items.map {
                    if (it.id == intent.id) it.copy(processed = true) else it
                },
            ),
        )
        is InboxIntent.PromoteToTask -> {
            val item = current.items.firstOrNull { it.id == intent.id }
                ?: return InboxReduceResult(current)
            val task = LifeTask(
                id = "inbox-${item.id}",
                title = item.text,
                durationMinutes = intent.durationMinutes.coerceIn(5, 240),
                constraintType = ConstraintType.FLUID,
                status = TaskStatus.PENDING,
                expirationPolicy = TaskExpirationPolicy.EndOfDay,
                scheduledDate = intent.day,
                tags = listOf("inbox", "capture"),
            )
            val next = current.copy(
                items = current.items.map {
                    if (it.id == intent.id) it.copy(processed = true) else it
                },
            )
            InboxReduceResult(next, spawnedTask = task)
        }
    }
}
