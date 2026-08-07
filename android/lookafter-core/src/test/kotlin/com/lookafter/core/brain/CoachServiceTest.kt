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
        val primary = CoachService { msg, _, _, _ -> "REMOTE:$msg" }
        val coach = FallbackCoachService(primary = primary, fallback = OfflineCoachService())
        val reply = coach.reply("hello", LifeState.EMPTY)
        assertTrue(reply.startsWith("REMOTE:"))
    }

    @Test
    fun fallbackWhenPrimaryThrows() = runTest {
        val boom = CoachService { _, _, _, _ -> error("network") }
        val coach = FallbackCoachService(primary = boom, fallback = OfflineCoachService())
        val reply = coach.reply("focus", LifeState.EMPTY)
        assertTrue(reply.isNotBlank())
    }
}
