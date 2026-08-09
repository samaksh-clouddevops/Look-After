package com.lookafter.core.planning

import com.lookafter.core.engine.LifeState
import com.lookafter.core.engine.LookAfterIntent
import com.lookafter.core.health.HealthSummary
import com.lookafter.core.serialization.InstantSerializer
import java.time.Instant
import java.time.LocalDate
import java.util.UUID
import kotlinx.serialization.Serializable

@Serializable
enum class PlanningSpeaker { USER, COACH, SYSTEM }

@Serializable
data class PlanningMessage(
    val id: String = UUID.randomUUID().toString(),
    val speaker: PlanningSpeaker,
    val text: String,
    @Serializable(with = InstantSerializer::class)
    val at: Instant = Instant.EPOCH,
)

@Serializable
data class PendingPlan(
    val id: String = UUID.randomUUID().toString(),
    val proposal: PlanProposal = PlanProposal(),
    val sourceLabel: String = "offline",
    val conversationalReply: String = "",
    val accepted: Boolean? = null,
)

/** Planning horizon picker values (days). */
object PlanningHorizons {
    val OPTIONS: List<Int> = listOf(1, 3, 7)
    const val DEFAULT: Int = 3
}

@Serializable
data class PlanningConversationState(
    val messages: List<PlanningMessage> = emptyList(),
    val pending: PendingPlan? = null,
    val appliedCount: Int = 0,
    /** Multi-day planning window selected in Brain UI. */
    val horizonDays: Int = PlanningHorizons.DEFAULT,
) {
    val transcript: List<Pair<Boolean, String>>
        get() = messages.map { (it.speaker == PlanningSpeaker.USER) to it.text }

    val pendingDiffLines: List<PlanMutationDiff.Line>
        get() = pending?.let { PlanMutationDiff.lines(it.proposal) }.orEmpty()
}

sealed class PlanningConversationIntent {
    data class UserMessage(
        val text: String,
        val now: Instant = Instant.now(),
    ) : PlanningConversationIntent()

    data class OfferPlan(
        val proposal: PlanProposal,
        val reply: String,
        val sourceLabel: String,
        val now: Instant = Instant.now(),
    ) : PlanningConversationIntent()

    data class CoachReply(val text: String, val now: Instant = Instant.now()) : PlanningConversationIntent()

    data class SetHorizonDays(val days: Int) : PlanningConversationIntent()

    data object AcceptPending : PlanningConversationIntent()
    data object RejectPending : PlanningConversationIntent()
    data object Clear : PlanningConversationIntent()
}

data class PlanningApplyBundle(
    val state: PlanningConversationState,
    val intents: List<LookAfterIntent> = emptyList(),
    val statusLine: String? = null,
)

/**
 * Multi-turn planning conversation — holds chat + pending proposal until accept/reject.
 * Mirrors iOS planning VM flow (propose → review → commit).
 */
object PlanningConversationEngine {

    fun reduce(
        current: PlanningConversationState,
        intent: PlanningConversationIntent,
    ): PlanningApplyBundle = when (intent) {
        is PlanningConversationIntent.UserMessage -> {
            val trimmed = intent.text.trim()
            if (trimmed.isEmpty()) PlanningApplyBundle(current)
            else PlanningApplyBundle(
                current.copy(
                    messages = current.messages + PlanningMessage(
                        speaker = PlanningSpeaker.USER,
                        text = trimmed,
                        at = intent.now,
                    ),
                ),
            )
        }
        is PlanningConversationIntent.OfferPlan -> {
            val pending = PendingPlan(
                proposal = intent.proposal,
                sourceLabel = intent.sourceLabel,
                conversationalReply = intent.reply,
            )
            val hasMut = intent.proposal.mutations.isNotEmpty()
            val coachText = buildString {
                append(intent.reply)
                if (hasMut) {
                    append("\n\nProposed **${intent.proposal.mutations.size}** change(s)")
                    append(" · ${intent.sourceLabel}. Accept to apply.")
                }
            }
            PlanningApplyBundle(
                current.copy(
                    pending = if (hasMut) pending else null,
                    messages = current.messages + PlanningMessage(
                        speaker = PlanningSpeaker.COACH,
                        text = coachText,
                        at = intent.now,
                    ),
                ),
                statusLine = if (hasMut) "Plan ready · review to apply" else null,
            )
        }
        is PlanningConversationIntent.CoachReply -> PlanningApplyBundle(
            current.copy(
                messages = current.messages + PlanningMessage(
                    speaker = PlanningSpeaker.COACH,
                    text = intent.text,
                    at = intent.now,
                ),
            ),
        )
        PlanningConversationIntent.AcceptPending -> {
            val pending = current.pending
                ?: return PlanningApplyBundle(current, statusLine = "No pending plan")
            // Intents filled by caller with PlanMutationApplier against live LifeState.
            PlanningApplyBundle(
                state = current.copy(
                    pending = pending.copy(accepted = true),
                    appliedCount = current.appliedCount + pending.proposal.mutations.size,
                    messages = current.messages + PlanningMessage(
                        speaker = PlanningSpeaker.SYSTEM,
                        text = "Applied ${pending.proposal.mutations.size} plan change(s).",
                    ),
                ),
                statusLine = "Plan applied",
            )
        }
        PlanningConversationIntent.RejectPending -> PlanningApplyBundle(
            current.copy(
                pending = current.pending?.copy(accepted = false),
                messages = current.messages + PlanningMessage(
                    speaker = PlanningSpeaker.SYSTEM,
                    text = "Plan discarded.",
                ),
            ),
            statusLine = "Plan discarded",
        )
        is PlanningConversationIntent.SetHorizonDays -> {
            val days = intent.days.coerceIn(1, 14)
            PlanningApplyBundle(
                current.copy(horizonDays = days),
                statusLine = "Horizon ${days}d",
            )
        }
        PlanningConversationIntent.Clear -> PlanningApplyBundle(
            // Keep horizon preference across clear.
            PlanningConversationState(horizonDays = current.horizonDays),
        )
    }

    fun intentsForPending(pending: PendingPlan, life: LifeState): List<LookAfterIntent> =
        PlanMutationApplier.apply(pending.proposal, life).intents

    fun offlineTurn(
        message: String,
        life: LifeState,
        today: LocalDate = life.currentDay ?: LocalDate.now(),
        horizonDays: Int = PlanningHorizons.DEFAULT,
    ): Pair<PlanProposal, String> {
        val multi = MultiDayPlanEngine.interpret(
            message = message,
            state = life,
            today = today,
            horizonDays = horizonDays.coerceIn(1, 14),
        )
        if (multi.proposal.mutations.isNotEmpty()) {
            return multi.proposal to multi.conversationalReply
        }
        val simple = MultiDayPlanEngine.simpleIntents(message, life)
        // Encode simple intents as empty proposal; caller applies simple intents directly.
        return PlanProposal(summary = simple.reply, mutations = emptyList()) to simple.reply
    }

    /** Cap transcript size for persistence (tail-only). */
    fun compactForStorage(
        state: PlanningConversationState,
        maxMessages: Int = 80,
    ): PlanningConversationState {
        if (state.messages.size <= maxMessages) return state
        return state.copy(messages = state.messages.takeLast(maxMessages))
    }
}
