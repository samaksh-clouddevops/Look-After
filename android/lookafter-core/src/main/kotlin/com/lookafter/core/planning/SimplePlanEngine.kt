package com.lookafter.core.planning

import com.lookafter.core.engine.LifeState
import com.lookafter.core.engine.LookAfterIntent
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.Priority
import com.lookafter.core.models.TaskStatus
import java.util.Locale

/**
 * Offline planning assistant — deterministic intents from a short user message.
 * Not a full multi-day planner; bridges until the LLM planning applier lands.
 */
object SimplePlanEngine {

    data class PlanTurn(
        val reply: String,
        val intents: List<LookAfterIntent> = emptyList(),
    )

    fun interpret(message: String, state: LifeState): PlanTurn {
        val q = message.trim().lowercase(Locale.US)
        if (q.isEmpty()) {
            return PlanTurn("Tell me what to adjust — park noise, protect focus, or clear done work.")
        }
        return when {
            q.contains("overwhelm") || q.contains("too much") || q.contains("strip") ->
                stripToHero(state)
            q.contains("park fluid") || q.contains("clear fluid") ->
                parkAllFluid(state)
            q.contains("someday") ->
                moveLowToSomeday(state)
            q.contains("protect") && q.contains("anchored") ->
                PlanTurn(
                    "Anchored blocks stay put. Finish or reschedule them intentionally on Today.",
                )
            else ->
                PlanTurn(
                    "I can: “strip the board”, “park fluid”, or “someday low priority”. " +
                        "Or open Brain for the hero coaching path.",
                )
        }
    }

    private fun stripToHero(state: LifeState): PlanTurn {
        val open = state.activeTasks.filter { it.status.isActive }
        if (open.isEmpty()) return PlanTurn("Board is already clear.")
        val hero = open
            .sortedWith(
                compareByDescending<LifeTask> {
                    when (it.constraintType) {
                        ConstraintType.ANCHORED -> 3
                        ConstraintType.FLEXIBLE -> 2
                        ConstraintType.FLUID -> 1
                    }
                }.thenByDescending { it.priority.rankBonus },
            )
            .first()
        val toPark = open.filter {
            it.id != hero.id && it.constraintType != ConstraintType.ANCHORED
        }
        val intents = toPark.map {
            LookAfterIntent.ParkTask(it.id, reason = "plan_strip")
        }
        return PlanTurn(
            reply = "Keeping **${hero.title}**. Parking ${toPark.size} non-anchored item(s).",
            intents = intents,
        )
    }

    private fun parkAllFluid(state: LifeState): PlanTurn {
        val fluid = state.activeTasks.filter {
            it.status.isActive && it.constraintType == ConstraintType.FLUID
        }
        if (fluid.isEmpty()) return PlanTurn("No fluid tasks to park.")
        return PlanTurn(
            reply = "Parking ${fluid.size} fluid task(s).",
            intents = fluid.map { LookAfterIntent.ParkTask(it.id, reason = "plan_park_fluid") },
        )
    }

    private fun moveLowToSomeday(state: LifeState): PlanTurn {
        val lows = state.activeTasks.filter {
            it.status.isActive &&
                (it.priority == Priority.LOW || it.priority == Priority.SOMEDAY)
        }
        if (lows.isEmpty()) return PlanTurn("No low-priority active tasks.")
        return PlanTurn(
            reply = "Moving ${lows.size} low/someday item(s) to the vault.",
            intents = lows.map { LookAfterIntent.MoveToSomeday(it.id) },
        )
    }
}
