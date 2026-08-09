package com.lookafter.core.brain

import com.lookafter.core.capacity.CapacityBand
import com.lookafter.core.engine.LifeState
import com.lookafter.core.health.HealthSummary
import com.lookafter.core.models.LifeTask
import java.time.Instant
import java.time.ZoneId

/**
 * Offline Executive Brain — pure decision + coach text without LLM.
 * Cloud / LLM coach can later replace [coachLine] while keeping [WorldState] as SSOT.
 */
object ExecutiveBrainEngine {

    fun tick(
        life: LifeState,
        health: HealthSummary = HealthSummary.EMPTY,
        now: Instant = Instant.now(),
        zone: ZoneId = ZoneId.systemDefault(),
        calendarEvents: List<WorldStateBuilder.CalendarEvent> = emptyList(),
        isInFlowSession: Boolean = false,
    ): BrainTick {
        val world = WorldStateBuilder.build(
            WorldStateBuilder.Input(
                life = life,
                health = health,
                now = now,
                zone = zone,
                calendarEvents = calendarEvents,
                isInFlowSession = isInFlowSession,
            ),
        )
        val byId = life.activeTasks.associateBy { it.id }
        val topTasks = world.topTaskIds.mapNotNull { byId[it] }
        val hero = world.heroTaskId?.let { byId[it] }
        val decision = decide(world, hero)
        return BrainTick(world = world, decision = decision, topTasks = topTasks)
    }

    fun coachReply(
        userMessage: String,
        life: LifeState,
        health: HealthSummary = HealthSummary.EMPTY,
        now: Instant = Instant.now(),
    ): String {
        val tick = tick(life, health, now)
        val q = userMessage.trim().lowercase()
        return when {
            q.isEmpty() -> tick.decision.coachLine
            q.contains("overwhelm") || q.contains("too much") ->
                overwhelmReply(tick.world)
            q.contains("med") || q.contains("pill") ->
                medReply(tick.world)
            q.contains("sleep") || q.contains("tired") ->
                sleepReply(tick.world)
            q.contains("focus") || q.contains("start") ->
                "Start with **${tick.decision.heroTitle}**. ${tick.decision.reason}"
            q.contains("what next") || q.contains("next") ->
                "Next move: **${tick.decision.heroTitle}**. ${tick.decision.reason}"
            else ->
                "I hear you. Right now I'd protect **${tick.decision.heroTitle}** — ${tick.decision.reason} " +
                    "Energy reads ${"%.0f".format(tick.world.currentEnergy * 100)}% " +
                    "(${tick.world.cognitiveLoad.name.lowercase()} load)."
        }
    }

    private fun decide(world: WorldState, hero: LifeTask?): BrainDecision {
        val title = hero?.title ?: "Nothing queued"
        val reason = world.heroReason.ifBlank { "Protect the quiet." }
        val action = when {
            hero == null -> "Open Capture"
            world.isInFlowSession -> "Continue block"
            else -> "Begin"
        }
        val coach = buildCoachLine(world, title, reason)
        val confidence = when (world.cognitiveLoad) {
            CognitiveLoadLevel.LOW -> 0.85
            CognitiveLoadLevel.MODERATE -> 0.75
            CognitiveLoadLevel.HIGH -> 0.6
            CognitiveLoadLevel.OVERLOADED -> 0.45
        }
        return BrainDecision(
            heroTaskId = hero?.id,
            heroTitle = title,
            reason = reason,
            actionLabel = action,
            confidence = confidence,
            coachLine = coach,
        )
    }

    private fun buildCoachLine(world: WorldState, title: String, reason: String): String {
        val loadHint = when {
            world.isOverCommitted ->
                "Board exceeds capacity — favor ≤${world.recommendedFocusMinutes}m focus."
            world.cognitiveLoad == CognitiveLoadLevel.OVERLOADED ->
                "Load is high — one small step only."
            world.cognitiveLoad == CognitiveLoadLevel.HIGH ->
                "Keep the board narrow (${world.capacityBand.label.lowercase()} capacity)."
            world.calendarDensity == CalendarDensity.PACKED ->
                "Calendar is packed — protect buffers around meetings."
            else -> "You have room to move (${world.capacityBand.label.lowercase()} capacity)."
        }
        return when (val med = world.medicationStatus) {
            is MedicationWorldStatus.DueNow ->
                "Medication due: ${med.names.joinToString()}. Then $title. $reason"
            is MedicationWorldStatus.MissedToday ->
                "Missed meds (${med.names.joinToString()}). Reset gently, then $title."
            else -> "$loadHint Next: $title — $reason"
        }
    }

    private fun overwhelmReply(world: WorldState): String =
        "Strip the board. One task: leave only the next intentional block. " +
            "Load=${world.cognitiveLoad.name.lowercase()}, open=${world.openTaskCount}, " +
            "calendar=${world.calendarDensity.label}, capacity=${world.capacityBand.label.lowercase()}, " +
            "pressure=${"%.0f".format(world.openTaskPressure * 100)}%."

    private fun medReply(world: WorldState): String = when (val m = world.medicationStatus) {
        is MedicationWorldStatus.DueNow -> "Take: ${m.names.joinToString()} (risk=${world.medicationRisk.label})."
        is MedicationWorldStatus.Upcoming -> "Upcoming: ${m.names.joinToString()}."
        MedicationWorldStatus.AllTakenToday -> "All meds marked taken. Nice."
        MedicationWorldStatus.NoneConfigured -> "No meds configured. Add them under You → Medication."
        is MedicationWorldStatus.MissedToday -> "Still open: ${m.names.joinToString()} (risk=${world.medicationRisk.label})."
        MedicationWorldStatus.Unknown -> "Medication status unknown."
    }

    private fun sleepReply(world: WorldState): String {
        val h = world.sleepHoursLastNight
        return if (h == null) {
            "No sleep data yet. Keep the first block short and protective " +
                "(${world.capacityBand.label.lowercase()} capacity · ~${world.recommendedFocusMinutes}m)."
        } else {
            "Sleep ${"%.1f".format(h)}h (${world.sleepQuality.name.lowercase()}). " +
                "Readiness ${"%.0f".format(world.healthReadiness * 100)}% · " +
                "capacity ${world.capacityBand.label.lowercase()} — bias toward ${
                    if (world.healthReadiness < 0.45 || world.capacityBand == CapacityBand.RECOVERY) {
                        "recovery tasks"
                    } else {
                        "priority work"
                    }
                }."
        }
    }
}
