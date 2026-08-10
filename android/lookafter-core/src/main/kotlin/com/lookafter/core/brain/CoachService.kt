package com.lookafter.core.brain

import com.lookafter.core.engine.LifeState
import com.lookafter.core.health.HealthSummary
import java.time.Instant

/**
 * Pluggable Executive Brain coach.
 * Production can swap [OfflineCoachService] for a network LLM implementation
 * without touching UI or LifeEngine.
 */
/**
 * Pluggable coach contract.
 * Not a fun-interface: default args on the abstract method are required for callers.
 */
interface CoachService {
    /**
     * @return coach reply text. Implementations should not throw.
     */
    suspend fun reply(
        userMessage: String,
        life: LifeState,
        health: HealthSummary = HealthSummary.EMPTY,
        now: Instant = Instant.now(),
    ): String
}

/** Deterministic local coach — default for offline / CI. */
class OfflineCoachService : CoachService {
    override suspend fun reply(
        userMessage: String,
        life: LifeState,
        health: HealthSummary,
        now: Instant,
    ): String = ExecutiveBrainEngine.coachReply(userMessage, life, health, now)
}

/**
 * Scaffold for a remote LLM coach.
 * Attempts [remote] and falls back to [fallback] on blank/error.
 * No network calls yet — [remote] is injected for tests / future wiring.
 */
class FallbackCoachService(
    private val primary: CoachService,
    private val fallback: CoachService = OfflineCoachService(),
) : CoachService {
    override suspend fun reply(
        userMessage: String,
        life: LifeState,
        health: HealthSummary,
        now: Instant,
    ): String {
        val primaryReply = runCatching {
            primary.reply(userMessage, life, health, now)
        }.getOrNull()?.trim().orEmpty()
        if (primaryReply.isNotEmpty()) return primaryReply
        return fallback.reply(userMessage, life, health, now)
    }
}

/**
 * Placeholder "remote" coach that returns empty so fallback kicks in.
 * Replace body with real HTTP/LLM when credentials exist.
 */
class UnconfiguredRemoteCoachService : CoachService {
    override suspend fun reply(
        userMessage: String,
        life: LifeState,
        health: HealthSummary,
        now: Instant,
    ): String = ""
}
