package com.lookafter.core.creativity

import com.lookafter.core.serialization.InstantSerializer
import java.time.Instant
import java.util.UUID
import kotlinx.serialization.Serializable

@Serializable
enum class CreativeSparkKind {
    NOTE,
    IDEA,
    SNIPPET,
    QUESTION,
    REFERENCE,
    ;

    val label: String
        get() = when (this) {
            NOTE -> "Note"
            IDEA -> "Idea"
            SNIPPET -> "Snippet"
            QUESTION -> "Question"
            REFERENCE -> "Reference"
        }
}

@Serializable
data class CreativeSpark(
    val id: String = UUID.randomUUID().toString(),
    val title: String = "",
    val body: String = "",
    val kind: CreativeSparkKind = CreativeSparkKind.IDEA,
    val tags: List<String> = emptyList(),
    val pinned: Boolean = false,
    @Serializable(with = InstantSerializer::class)
    val createdAt: Instant = Instant.EPOCH,
    @Serializable(with = InstantSerializer::class)
    val updatedAt: Instant = Instant.EPOCH,
)

@Serializable
data class CreativeBoard(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val subtitle: String = "",
    val sparkIds: List<String> = emptyList(),
    val colorHint: String = "green",
    @Serializable(with = InstantSerializer::class)
    val createdAt: Instant = Instant.EPOCH,
) {
    val sparkCount: Int get() = sparkIds.size
}

@Serializable
data class CreativityState(
    val boards: List<CreativeBoard> = emptyList(),
    val sparks: List<CreativeSpark> = emptyList(),
    val selectedBoardId: String? = null,
) {
    val selectedBoard: CreativeBoard?
        get() = boards.firstOrNull { it.id == selectedBoardId } ?: boards.firstOrNull()

    fun sparksForBoard(boardId: String): List<CreativeSpark> {
        val board = boards.firstOrNull { it.id == boardId } ?: return emptyList()
        val byId = sparks.associateBy { it.id }
        return board.sparkIds.mapNotNull { byId[it] }
    }

    val inboxSparks: List<CreativeSpark>
        get() {
            val claimed = boards.flatMap { it.sparkIds }.toSet()
            return sparks.filter { it.id !in claimed }.sortedByDescending { it.updatedAt }
        }

    companion object {
        val EMPTY = CreativityState()
    }
}

sealed class CreativityIntent {
    data class AddBoard(val board: CreativeBoard) : CreativityIntent()
    data class UpdateBoard(val board: CreativeBoard) : CreativityIntent()
    data class DeleteBoard(val id: String) : CreativityIntent()
    data class SelectBoard(val id: String?) : CreativityIntent()
    data class AddSpark(val spark: CreativeSpark, val boardId: String? = null) : CreativityIntent()
    data class UpdateSpark(val spark: CreativeSpark) : CreativityIntent()
    data class DeleteSpark(val id: String) : CreativityIntent()
    data class PinSpark(val id: String, val pinned: Boolean) : CreativityIntent()
    data class MoveSparkToBoard(val sparkId: String, val boardId: String?) : CreativityIntent()
    data class PromoteSparkToCapture(val sparkId: String) : CreativityIntent()
    data class ReplaceState(val state: CreativityState) : CreativityIntent()
}

/** Pure creativity boards reducer (Phase E4). */
object CreativityEngine {

    fun reduce(current: CreativityState, intent: CreativityIntent): CreativityState = when (intent) {
        is CreativityIntent.AddBoard -> {
            val board = normalizeBoard(intent.board)
            current.copy(
                boards = listOf(board) + current.boards,
                selectedBoardId = board.id,
            )
        }
        is CreativityIntent.UpdateBoard -> {
            val board = normalizeBoard(intent.board)
            current.copy(boards = current.boards.map { if (it.id == board.id) board else it })
        }
        is CreativityIntent.DeleteBoard -> current.copy(
            boards = current.boards.filterNot { it.id == intent.id },
            selectedBoardId = current.selectedBoardId?.takeIf { it != intent.id },
        )
        is CreativityIntent.SelectBoard -> current.copy(selectedBoardId = intent.id)
        is CreativityIntent.AddSpark -> {
            val spark = normalizeSpark(intent.spark)
            var boards = current.boards
            val boardId = intent.boardId ?: current.selectedBoardId
            if (boardId != null) {
                boards = boards.map { b ->
                    if (b.id == boardId && spark.id !in b.sparkIds) {
                        b.copy(sparkIds = listOf(spark.id) + b.sparkIds)
                    } else {
                        b
                    }
                }
            }
            current.copy(sparks = listOf(spark) + current.sparks, boards = boards)
        }
        is CreativityIntent.UpdateSpark -> {
            val spark = normalizeSpark(intent.spark)
            current.copy(sparks = current.sparks.map { if (it.id == spark.id) spark else it })
        }
        is CreativityIntent.DeleteSpark -> current.copy(
            sparks = current.sparks.filterNot { it.id == intent.id },
            boards = current.boards.map { b -> b.copy(sparkIds = b.sparkIds.filterNot { it == intent.id }) },
        )
        is CreativityIntent.PinSpark -> current.copy(
            sparks = current.sparks.map {
                if (it.id == intent.id) it.copy(pinned = intent.pinned, updatedAt = Instant.now()) else it
            },
        )
        is CreativityIntent.MoveSparkToBoard -> {
            var boards = current.boards.map { b ->
                b.copy(sparkIds = b.sparkIds.filterNot { it == intent.sparkId })
            }
            if (intent.boardId != null) {
                boards = boards.map { b ->
                    if (b.id == intent.boardId && intent.sparkId !in b.sparkIds) {
                        b.copy(sparkIds = listOf(intent.sparkId) + b.sparkIds)
                    } else {
                        b
                    }
                }
            }
            current.copy(boards = boards)
        }
        is CreativityIntent.PromoteSparkToCapture -> current // app layer turns spark into LifeTask
        is CreativityIntent.ReplaceState -> intent.state
    }

    fun defaultBoards(now: Instant = Instant.now()): List<CreativeBoard> = listOf(
        CreativeBoard(title = "Inbox sparks", subtitle = "Unsorted captures", createdAt = now),
        CreativeBoard(title = "Projects", subtitle = "Active creative threads", createdAt = now),
    )

    private fun normalizeBoard(board: CreativeBoard): CreativeBoard =
        board.copy(
            title = board.title.trim().ifBlank { "Board" },
            subtitle = board.subtitle.trim(),
        )

    private fun normalizeSpark(spark: CreativeSpark): CreativeSpark {
        val now = Instant.now()
        return spark.copy(
            title = spark.title.trim(),
            body = spark.body.trim(),
            tags = spark.tags.map { it.trim() }.filter { it.isNotEmpty() }.distinct(),
            createdAt = if (spark.createdAt.epochSecond <= 0) now else spark.createdAt,
            updatedAt = now,
        )
    }
}
