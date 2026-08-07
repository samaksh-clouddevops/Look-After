package com.lookafter.core.planning

import com.lookafter.core.engine.LifeState
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.Priority
import com.lookafter.core.models.TaskStatus
import java.time.LocalDate
import java.util.Locale

/**
 * Multi-day offline planner — expands short natural language into a [PlanProposal]
 * spanning several calendar days. LLM path can replace [fromLlmJson] parsing later.
 */
object MultiDayPlanEngine {

    data class Turn(
        val proposal: PlanProposal,
        val conversationalReply: String,
    )

    fun interpret(
        message: String,
        state: LifeState,
        today: LocalDate = state.currentDay ?: LocalDate.now(),
        horizonDays: Int = 3,
    ): Turn {
        val q = message.trim().lowercase(Locale.US)
        if (q.isEmpty()) {
            return Turn(
                proposal = PlanProposal(summary = "No changes."),
                conversationalReply = "Describe the week — e.g. “spread deep work across 3 days” or “clear tomorrow morning”.",
            )
        }

        // Explicit multi-day load balance
        if (q.contains("spread") || q.contains("across") || q.contains("multi") ||
            q.contains("next days") || q.contains("this week")
        ) {
            return spreadFlexibleWork(state, today, horizonDays.coerceIn(2, 7))
        }

        // Clear / lighten a named day
        if (q.contains("tomorrow")) {
            return lightenDay(state, today.plusDays(1), label = "tomorrow")
        }
        if (q.contains("today") && (q.contains("clear") || q.contains("lighten") || q.contains("protect"))) {
            return lightenDay(state, today, label = "today")
        }

        // Seed a simple morning focus block each day of the horizon
        if (q.contains("morning focus") || q.contains("morning blocks") || q.contains("deep mornings")) {
            return seedMorningBlocks(today, horizonDays.coerceIn(2, 5))
        }

        // Fall back to single-day SimplePlanEngine via empty proposal + handoff text
        val simple = SimplePlanEngine.interpret(message, state)
        val mutations = simple.intents.mapNotNull { intent ->
            // SimplePlanEngine already produced intents — wrap as empty proposal + reply only.
            // Callers may apply simple.intents directly when mutations empty.
            null
        }
        return Turn(
            proposal = PlanProposal(
                summary = simple.reply,
                mutations = mutations,
                dayHorizon = 1,
            ),
            conversationalReply = simple.reply +
                if (simple.intents.isNotEmpty()) {
                    "\n_(Applied ${simple.intents.size} immediate adjustment(s).)_"
                } else {
                    "\nTry: “spread work across 3 days”, “morning focus this week”, “lighten tomorrow”."
                },
        )
    }

    /** Direct access to underlying single-day intents for ViewModel bridge. */
    fun simpleIntents(message: String, state: LifeState) =
        SimplePlanEngine.interpret(message, state)

    private fun spreadFlexibleWork(state: LifeState, today: LocalDate, days: Int): Turn {
        val flexible = state.activeTasks.filter {
            it.status.isActive &&
                it.constraintType != ConstraintType.ANCHORED &&
                it.priority != Priority.SOMEDAY
        }
        if (flexible.isEmpty()) {
            return Turn(
                PlanProposal(summary = "No flexible work to spread."),
                "Nothing flexible is open — capture work first, then ask to spread it.",
            )
        }
        val mutations = flexible.mapIndexed { index, task ->
            val day = today.plusDays((index % days).toLong())
            // Stagger late morning / afternoon
            val hour = 9 + (index % 3) * 2
            PlanMutation.RescheduleTask(
                taskId = task.id,
                day = day,
                hour = hour,
                minute = 0,
            )
        }
        val proposal = PlanProposal(
            summary = "Spread ${flexible.size} task(s) across $days day(s).",
            mutations = mutations,
            dayHorizon = days,
        )
        return Turn(
            proposal = proposal,
            conversationalReply = "I’ll distribute **${flexible.size}** non-anchored tasks over the next **$days** days, " +
                "keeping mornings lighter where possible. Review on Today after applying.",
        )
    }

    private fun lightenDay(state: LifeState, day: LocalDate, label: String): Turn {
        val onDay = state.activeTasks.filter {
            it.status.isActive &&
                it.scheduledDate == day &&
                it.constraintType == ConstraintType.FLUID
        }
        if (onDay.isEmpty()) {
            return Turn(
                PlanProposal(summary = "No fluid tasks on $label."),
                "No fluid noise on $label to park — anchored/flexible blocks stay.",
            )
        }
        val mutations = onDay.map {
            PlanMutation.ParkTask(taskId = it.id, reason = "plan_lighten_$label")
        }
        return Turn(
            PlanProposal(
                summary = "Park ${onDay.size} fluid task(s) from $label.",
                mutations = mutations,
            ),
            "Lightening **$label** by parking ${onDay.size} fluid item(s).",
        )
    }

    private fun seedMorningBlocks(today: LocalDate, days: Int): Turn {
        val mutations = (0 until days).map { offset ->
            val day = today.plusDays(offset.toLong())
            PlanMutation.CreateTask(
                title = "Deep work block",
                durationMinutes = 50,
                constraint = ConstraintType.FLEXIBLE,
                priority = Priority.HIGH,
                day = day,
                hour = 9,
                minute = 0,
                tags = listOf("plan", "deep-work"),
                notes = "Protected focus — multi-day seed",
            )
        }
        return Turn(
            PlanProposal(
                summary = "Seed $days morning deep-work block(s).",
                mutations = mutations,
                dayHorizon = days,
            ),
            "Scheduled a **50-minute deep work** block at 9:00 for the next **$days** mornings.",
        )
    }
}
