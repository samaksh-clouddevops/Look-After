package com.lookafter.core.planning

import com.lookafter.core.engine.LifeState
import com.lookafter.core.engine.LookAfterIntent
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.Priority
import com.lookafter.core.models.RecurrenceRule
import com.lookafter.core.models.TaskExpirationPolicy
import com.lookafter.core.models.TaskStatus
import com.lookafter.core.serialization.InstantSerializer
import com.lookafter.core.serialization.LocalDateSerializer
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.util.UUID
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Declarative plan mutations — mirrors iOS `PlanMutation` (subset).
 * Produced by offline or LLM planners; applied via [PlanMutationApplier].
 */
@Serializable
sealed class PlanMutation {
    @Serializable
    @SerialName("createTask")
    data class CreateTask(
        val title: String,
        val durationMinutes: Int = 30,
        val constraint: ConstraintType = ConstraintType.FLEXIBLE,
        val priority: Priority = Priority.MEDIUM,
        val recurrence: RecurrenceRule = RecurrenceRule.NONE,
        @Serializable(with = LocalDateSerializer::class)
        val day: LocalDate? = null,
        val hour: Int? = null,
        val minute: Int? = null,
        val notes: String = "",
        val tags: List<String> = emptyList(),
    ) : PlanMutation()

    @Serializable
    @SerialName("completeTask")
    data class CompleteTask(val taskId: String) : PlanMutation()

    @Serializable
    @SerialName("parkTask")
    data class ParkTask(val taskId: String, val reason: String = "plan") : PlanMutation()

    @Serializable
    @SerialName("moveToSomeday")
    data class MoveToSomeday(val taskId: String) : PlanMutation()

    @Serializable
    @SerialName("rescheduleTask")
    data class RescheduleTask(
        val taskId: String,
        @Serializable(with = LocalDateSerializer::class)
        val day: LocalDate,
        val hour: Int? = null,
        val minute: Int? = null,
        val durationMinutes: Int? = null,
    ) : PlanMutation()

    @Serializable
    @SerialName("updateTitle")
    data class UpdateTitle(val taskId: String, val title: String) : PlanMutation()

    @Serializable
    @SerialName("deleteTask")
    data class DeleteTask(val taskId: String) : PlanMutation()
}

@Serializable
data class PlanProposal(
    val summary: String = "",
    val mutations: List<PlanMutation> = emptyList(),
    val dayHorizon: Int = 1,
    @Serializable(with = InstantSerializer::class)
    val generatedAt: Instant = Instant.EPOCH,
)

data class ApplyResult(
    val intents: List<LookAfterIntent> = emptyList(),
    val appliedCount: Int = 0,
    val skipped: List<String> = emptyList(),
    val reply: String = "",
)

/**
 * Turns [PlanMutation]s into [LookAfterIntent]s against the current [LifeState].
 */
object PlanMutationApplier {

    fun apply(
        proposal: PlanProposal,
        state: LifeState,
        zone: ZoneId = ZoneId.systemDefault(),
        now: Instant = Instant.now(),
    ): ApplyResult {
        val intents = mutableListOf<LookAfterIntent>()
        val skipped = mutableListOf<String>()
        val today = state.currentDay ?: now.atZone(zone).toLocalDate()

        for (m in proposal.mutations) {
            when (m) {
                is PlanMutation.CreateTask -> {
                    val day = m.day ?: today
                    val start = scheduleInstant(day, m.hour, m.minute, zone)
                    val end = start?.plusSeconds(m.durationMinutes.coerceIn(5, 480) * 60L)
                    val task = LifeTask(
                        id = "plan-${UUID.randomUUID()}",
                        title = m.title.trim().ifEmpty { "Untitled" },
                        durationMinutes = m.durationMinutes.coerceIn(5, 480),
                        constraintType = m.constraint,
                        status = TaskStatus.PENDING,
                        priority = m.priority,
                        recurrence = m.recurrence,
                        notes = m.notes,
                        scheduledDate = day,
                        scheduledStart = start,
                        scheduledEnd = end,
                        expirationPolicy = when (m.constraint) {
                            ConstraintType.ANCHORED, ConstraintType.FLUID ->
                                TaskExpirationPolicy.EndOfDay
                            ConstraintType.FLEXIBLE -> TaskExpirationPolicy.Infinite
                        },
                        tags = (m.tags + "plan").distinct(),
                        createdAt = now,
                        updatedAt = now,
                    )
                    intents += LookAfterIntent.AddTask(task)
                }
                is PlanMutation.CompleteTask -> {
                    if (state.taskById(m.taskId) == null) skipped += "complete missing ${m.taskId}"
                    else intents += LookAfterIntent.CompleteTask(m.taskId, now)
                }
                is PlanMutation.ParkTask -> {
                    if (state.taskById(m.taskId) == null) skipped += "park missing ${m.taskId}"
                    else intents += LookAfterIntent.ParkTask(m.taskId, m.reason)
                }
                is PlanMutation.MoveToSomeday -> {
                    if (state.taskById(m.taskId) == null) skipped += "someday missing ${m.taskId}"
                    else intents += LookAfterIntent.MoveToSomeday(m.taskId)
                }
                is PlanMutation.DeleteTask -> {
                    if (state.taskById(m.taskId) == null) skipped += "delete missing ${m.taskId}"
                    else intents += LookAfterIntent.DeleteTask(m.taskId)
                }
                is PlanMutation.RescheduleTask -> {
                    val task = state.taskById(m.taskId)
                    if (task == null) {
                        skipped += "reschedule missing ${m.taskId}"
                        continue
                    }
                    val mins = m.durationMinutes ?: task.durationMinutes
                    val start = scheduleInstant(m.day, m.hour, m.minute, zone)
                        ?: task.scheduledStart
                    val end = start?.plusSeconds(mins.coerceIn(5, 480) * 60L)
                    intents += LookAfterIntent.UpdateTask(
                        task.copy(
                            scheduledDate = m.day,
                            scheduledStart = start,
                            scheduledEnd = end,
                            durationMinutes = mins,
                            updatedAt = now,
                        ),
                    )
                }
                is PlanMutation.UpdateTitle -> {
                    val task = state.taskById(m.taskId)
                    if (task == null) {
                        skipped += "title missing ${m.taskId}"
                        continue
                    }
                    intents += LookAfterIntent.UpdateTask(
                        task.copy(title = m.title.trim(), updatedAt = now),
                    )
                }
            }
        }

        val reply = buildString {
            append(proposal.summary.ifBlank { "Applied ${intents.size} change(s)." })
            if (skipped.isNotEmpty()) append(" Skipped: ${skipped.size}.")
        }
        return ApplyResult(
            intents = intents,
            appliedCount = intents.size,
            skipped = skipped,
            reply = reply,
        )
    }

    private fun scheduleInstant(
        day: LocalDate,
        hour: Int?,
        minute: Int?,
        zone: ZoneId,
    ): Instant? {
        val h = hour ?: return null
        if (h !in 0..23) return null
        val m = (minute ?: 0).coerceIn(0, 59)
        return day.atTime(LocalTime.of(h, m)).atZone(zone).toInstant()
    }
}
