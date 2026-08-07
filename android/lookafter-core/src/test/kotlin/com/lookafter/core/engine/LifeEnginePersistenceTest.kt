package com.lookafter.core.engine

import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.TaskExpirationPolicy
import com.lookafter.core.models.TaskStatus
import com.lookafter.core.serialization.LookAfterJson
import java.time.LocalDate
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.encodeToString

class LifeEnginePersistenceTest {

    @Test
    fun `LifeState JSON round-trip preserves tasks and logs`() {
        val day = LocalDate.of(2026, 3, 11)
        val state = LifeState(
            activeTasks = listOf(
                LifeTask(
                    id = "t1",
                    title = "Dinner",
                    expirationPolicy = TaskExpirationPolicy.EndOfDay,
                    status = TaskStatus.PENDING,
                    scheduledDate = day,
                ),
            ),
            consecutiveHighLoadDays = 2,
            currentDay = day,
        )
        val json = LookAfterJson.codec.encodeToString(state)
        val decoded = LookAfterJson.codec.decodeFromString(LifeState.serializer(), json)
        assertEquals(state.activeTasks.single().id, decoded.activeTasks.single().id)
        assertEquals(TaskExpirationPolicy.EndOfDay, decoded.activeTasks.single().expirationPolicy)
        assertEquals(day, decoded.currentDay)
        assertEquals(2, decoded.consecutiveHighLoadDays)
    }

    @Test
    fun `hydrate loads repository snapshot over fallback`() = runTest {
        val zone = ZoneOffset.UTC
        val stored = LifeState(
            activeTasks = listOf(LifeTask(id = "stored", title = "From disk")),
            currentDay = LocalDate.of(2026, 3, 10),
        )
        val repo = InMemoryLifeStateRepository(initial = stored)
        val engine = LifeEngine(initialState = LifeState.EMPTY, repository = repo)

        val hydrated = engine.hydrate(fallback = LifeState(activeTasks = listOf(LifeTask(id = "fb", title = "Fallback"))))
        assertEquals("stored", hydrated.activeTasks.single().id)
        assertEquals("stored", engine.state.value.activeTasks.single().id)
    }

    @Test
    fun `process persists updated state via repository`() = runTest {
        val repo = InMemoryLifeStateRepository()
        val engine = LifeEngine(initialState = LifeState.EMPTY, repository = repo)
        engine.hydrate(fallback = LifeState.EMPTY)

        val task = LifeTask(id = "new-1", title = "Inbox")
        engine.process(LookAfterIntent.AddTask(task))

        val loaded = repo.load()
        assertNotNull(loaded)
        assertEquals(1, loaded.activeTasks.size)
        assertEquals("new-1", loaded.activeTasks.single().id)

        // Second engine instance sees the snapshot.
        val engine2 = LifeEngine(repository = repo)
        engine2.hydrate()
        assertTrue(engine2.state.value.activeTasks.any { it.id == "new-1" })
    }
}
