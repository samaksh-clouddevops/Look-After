package com.lookafter.core.brain

import com.lookafter.core.engine.LifeState
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.TaskStatus
import kotlin.test.Test
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest

class CoachServiceTest {

    @Test
    fun offlineCoachReturnsGuidance() = runTest {
        val life = LifeState(
            activeTasks = listOf(
                LifeTask(id = "1", title = "Write brief", status = TaskStatus.PENDING),
            ),
        )
        val reply = OfflineCoachService().reply("what next", life)
        assertTrue(reply.contains("Write brief") || reply.lowercase().contains("next"))
    }

    @Test
    fun fallbackUsesSecondaryWhenPrimaryBlank() = runTest {
        val life = LifeState.EMPTY
        val coach = FallbackCoachService(
            primary = UnconfiguredRemoteCoachService(),
            fallback = OfflineCoachService(),
        )
        val reply = coach.reply("I'm tired", life)
        assertTrue(reply.isNotBlank())
    }

    @Test
    fun fallbackUsesPrimaryWhenPresent() = runTest {
        val primary = object : CoachService {
            override suspend fun reply(
                userMessage: String,
                life: LifeState,
                health: com.lookafter.core.health.HealthSummary,
                now: java.time.Instant,
            ): String = "REMOTE:$userMessage"
        }
        val coach = FallbackCoachService(primary = primary, fallback = OfflineCoachService())
        val reply = coach.reply("hello", LifeState.EMPTY)
        assertTrue(reply.startsWith("REMOTE:"))
    }

    @Test
    fun fallbackWhenPrimaryThrows() = runTest {
        val boom = object : CoachService {
            override suspend fun reply(
                userMessage: String,
                life: LifeState,
                health: com.lookafter.core.health.HealthSummary,
                now: java.time.Instant,
            ): String = error("network")
        }
        val coach = FallbackCoachService(primary = boom, fallback = OfflineCoachService())
        val reply = coach.reply("focus", LifeState.EMPTY)
        assertTrue(reply.isNotBlank())
    }
}
