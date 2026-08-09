package com.lookafter.core.creativity

import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class CreativityEngineTest {

    private val now = Instant.parse("2026-08-08T12:00:00Z")

    @Test
    fun addBoardAndSpark() {
        var state = CreativityState.EMPTY
        val board = CreativeBoard(id = "b1", title = " Projects ", createdAt = now)
        state = CreativityEngine.reduce(state, CreativityIntent.AddBoard(board))
        assertEquals("Projects", state.boards.single().title)
        assertEquals("b1", state.selectedBoardId)

        val spark = CreativeSpark(id = "s1", title = " Logo ", kind = CreativeSparkKind.IDEA, createdAt = now)
        state = CreativityEngine.reduce(state, CreativityIntent.AddSpark(spark, boardId = "b1"))
        assertEquals(1, state.sparks.size)
        assertEquals(listOf("s1"), state.boards.single().sparkIds)
        assertEquals("Logo", state.sparks.single().title)
    }

    @Test
    fun pinMoveAndDelete() {
        var state = CreativityEngine.reduce(
            CreativityState.EMPTY,
            CreativityIntent.AddBoard(CreativeBoard(id = "b1", title = "A", createdAt = now)),
        )
        state = CreativityEngine.reduce(
            state,
            CreativityIntent.AddBoard(CreativeBoard(id = "b2", title = "B", createdAt = now)),
        )
        state = CreativityEngine.reduce(
            state,
            CreativityIntent.AddSpark(CreativeSpark(id = "s1", title = "x", createdAt = now), "b1"),
        )
        state = CreativityEngine.reduce(state, CreativityIntent.PinSpark("s1", true))
        assertTrue(state.sparks.single().pinned)
        state = CreativityEngine.reduce(state, CreativityIntent.MoveSparkToBoard("s1", "b2"))
        assertTrue(state.boards.first { it.id == "b1" }.sparkIds.isEmpty())
        assertEquals(listOf("s1"), state.boards.first { it.id == "b2" }.sparkIds)
        state = CreativityEngine.reduce(state, CreativityIntent.DeleteSpark("s1"))
        assertTrue(state.sparks.isEmpty())
        assertTrue(state.boards.all { it.sparkIds.isEmpty() })
    }

    @Test
    fun inboxSparksUnassigned() {
        var state = CreativityEngine.reduce(
            CreativityState.EMPTY,
            CreativityIntent.AddSpark(CreativeSpark(id = "s1", title = "loose", createdAt = now), boardId = null),
        )
        assertEquals(1, state.inboxSparks.size)
        assertEquals("s1", state.inboxSparks.single().id)
    }
}
