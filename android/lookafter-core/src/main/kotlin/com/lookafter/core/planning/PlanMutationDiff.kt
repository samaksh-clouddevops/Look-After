package com.lookafter.core.planning

/**
 * Human-readable review lines for a [PlanProposal] before Accept.
 * Mirrors iOS planning "diff before commit" surface.
 */
object PlanMutationDiff {

    data class Line(
        val kind: String,
        val summary: String,
        val detail: String = "",
    )

    fun lines(proposal: PlanProposal): List<Line> =
        proposal.mutations.map { describe(it) }

    fun describe(mutation: PlanMutation): Line = when (mutation) {
        is PlanMutation.CreateTask -> Line(
            kind = "Create",
            summary = mutation.title.ifBlank { "Untitled" },
            detail = buildString {
                append("${mutation.durationMinutes}m · ${mutation.constraint.name.lowercase()}")
                mutation.day?.let { append(" · $it") }
                if (mutation.hour != null) {
                    append(" @ %02d:%02d".format(mutation.hour, mutation.minute ?: 0))
                }
                if (mutation.priority != com.lookafter.core.models.Priority.MEDIUM) {
                    append(" · ${mutation.priority.name.lowercase()}")
                }
            },
        )
        is PlanMutation.CompleteTask -> Line(
            kind = "Complete",
            summary = "Task ${shortId(mutation.taskId)}",
            detail = mutation.taskId,
        )
        is PlanMutation.ParkTask -> Line(
            kind = "Park",
            summary = "Task ${shortId(mutation.taskId)}",
            detail = mutation.reason.ifBlank { "park" },
        )
        is PlanMutation.MoveToSomeday -> Line(
            kind = "Someday",
            summary = "Task ${shortId(mutation.taskId)}",
        )
        is PlanMutation.RescheduleTask -> Line(
            kind = "Reschedule",
            summary = "Task ${shortId(mutation.taskId)} → ${mutation.day}",
            detail = buildString {
                if (mutation.hour != null) {
                    append("%02d:%02d".format(mutation.hour, mutation.minute ?: 0))
                }
                mutation.durationMinutes?.let {
                    if (isNotEmpty()) append(" · ")
                    append("${it}m")
                }
            },
        )
        is PlanMutation.UpdateTitle -> Line(
            kind = "Rename",
            summary = mutation.title,
            detail = shortId(mutation.taskId),
        )
        is PlanMutation.DeleteTask -> Line(
            kind = "Delete",
            summary = "Task ${shortId(mutation.taskId)}",
        )
    }

    fun headline(proposal: PlanProposal): String {
        if (proposal.mutations.isEmpty()) {
            return proposal.summary.ifBlank { "No changes" }
        }
        val counts = proposal.mutations.groupingBy { describe(it).kind }.eachCount()
        val parts = counts.entries.joinToString(" · ") { "${it.value} ${it.key.lowercase()}" }
        val horizon = if (proposal.dayHorizon > 1) " · ${proposal.dayHorizon}d" else ""
        return (proposal.summary.ifBlank { parts }) + horizon
    }

    private fun shortId(id: String): String =
        if (id.length <= 10) id else id.take(8) + "…"
}
