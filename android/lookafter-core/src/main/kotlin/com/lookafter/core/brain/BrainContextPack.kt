package com.lookafter.core.brain

import com.lookafter.core.engine.LifeState
import com.lookafter.core.models.TaskStatus

/**
 * Shared context blobs for offline coach, LLM coach, and plan prompts.
 * Keeps Android/iOS-shaped field language in one pure place (Phase B2 / B5).
 */
object BrainContextPack {

    /** Compact system/context line for chat completions. */
    fun systemSummary(tick: BrainTick, horizonDays: Int = 1): String {
        val w = tick.world
        return buildString {
            append("Look After executive context. Horizon=${horizonDays}d. ")
            append("Hero=${tick.decision.heroTitle}. ")
            append("Capacity=${w.capacityBand.label} energy=${pct(w.capacityEnergyScore)} ")
            append("focus≈${w.recommendedFocusMinutes}m overCommitted=${w.isOverCommitted}. ")
            append("Load=${w.cognitiveLoad.name.lowercase()} pressure=${pct(w.openTaskPressure)}. ")
            append("Calendar=${w.calendarDensity.label} events=${w.calendarEventCount} ")
            append("meetingHeavy=${w.isMeetingHeavyDay}. ")
            append("Board open=${w.openTaskCount} (A${w.anchoredOpenCount}/X${w.flexibleOpenCount}/F${w.fluidOpenCount}) ")
            append("planned=${w.plannedOpenMinutes}m done=${w.completedTodayCount}. ")
            append("MedRisk=${w.medicationRisk.label}. ")
            append("Sleep=${w.sleepHoursLastNight?.let { "%.1f".format(it) + "h" } ?: "unknown"} ")
            append("readiness=${pct(w.healthReadiness)}. ")
            w.nextEventTitle?.let { next ->
                append("NextEvent=$next")
                w.minutesUntilNextEvent?.let { append(" in ${it}m") }
                append(". ")
            }
            append(tick.decision.coachLine)
        }.trim()
    }

    /** Multi-line planner brief for LLM JSON plan requests. */
    fun plannerBrief(life: LifeState, tick: BrainTick, horizonDays: Int): String {
        val w = tick.world
        val open = life.activeTasks.filter { it.status.isActive }.take(16)
        val lines = open.joinToString("\n") { t ->
            "- id=${t.id} | ${t.title} | ${t.constraintType} | ${t.priority} | " +
                "day=${t.scheduledDate} | ${t.durationMinutes}m | area=${t.area} project=${t.project}"
        }.ifBlank { "- none" }
        return buildString {
            appendLine(systemSummary(tick, horizonDays))
            appendLine("Open tasks:")
            appendLine(lines)
            appendLine(
                "Guidance: protect anchored; respect capacity ${w.capacityBand.label}; " +
                    "if overCommitted park fluid; calendar density ${w.calendarDensity.label}.",
            )
        }.trim()
    }

    /** Golden snapshot shape for tests / cross-platform field map. */
    fun fieldMap(world: WorldState): Map<String, String> = linkedMapOf(
        "capacityBand" to world.capacityBand.name,
        "capacityEnergyScore" to "%.2f".format(world.capacityEnergyScore),
        "recommendedFocusMinutes" to world.recommendedFocusMinutes.toString(),
        "isOverCommitted" to world.isOverCommitted.toString(),
        "cognitiveLoad" to world.cognitiveLoad.name,
        "openTaskPressure" to "%.2f".format(world.openTaskPressure),
        "calendarDensity" to world.calendarDensity.name,
        "calendarEventCount" to world.calendarEventCount.toString(),
        "isMeetingHeavyDay" to world.isMeetingHeavyDay.toString(),
        "medicationRisk" to world.medicationRisk.name,
        "anchoredOpenCount" to world.anchoredOpenCount.toString(),
        "flexibleOpenCount" to world.flexibleOpenCount.toString(),
        "fluidOpenCount" to world.fluidOpenCount.toString(),
        "plannedOpenMinutes" to world.plannedOpenMinutes.toString(),
        "openTaskCount" to world.openTaskCount.toString(),
        "healthReadiness" to "%.2f".format(world.healthReadiness),
        "sleepQuality" to world.sleepQuality.name,
    )

    private fun pct(v: Double): String = "%.0f%%".format(v * 100.0)
}
