package com.lookafter.core.engine

/**
 * Persistence boundary for [LifeState].
 *
 * Implemented in the app layer (DataStore / file / DB). Core only depends on
 * this interface — zero Android imports.
 */
interface LifeStateRepository {
    /** Load the last persisted universe, or null if none / corrupt. */
    suspend fun load(): LifeState?

    /** Atomically persist [state] (mimics iOS JSON snapshot writes). */
    suspend fun save(state: LifeState)
}

/**
 * In-memory repository for JVM unit tests and offline demos.
 */
class InMemoryLifeStateRepository(
    initial: LifeState? = null,
) : LifeStateRepository {
    @Volatile
    private var snapshot: LifeState? = initial

    override suspend fun load(): LifeState? = snapshot

    override suspend fun save(state: LifeState) {
        snapshot = state
    }
}
