package com.lookafter.app.ui.timeline

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.PauseCircle
import androidx.compose.material.icons.outlined.PlayCircle
import androidx.compose.material.icons.outlined.RadioButtonUnchecked
import androidx.compose.material.icons.outlined.Snooze
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.lookafter.app.ui.theme.LookAfterColors
import com.lookafter.app.ui.theme.LookAfterDimens
import com.lookafter.core.engine.LookAfterIntent
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.Priority
import com.lookafter.core.models.RecurrenceRule
import com.lookafter.core.models.TaskStatus
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * Timeline row for a single [LifeTask].
 *
 * Badge · title/meta · start/pause · park · complete. Tap body → edit.
 */
@Composable
fun TimelineTaskCard(
    task: LifeTask,
    onIntent: (LookAfterIntent) -> Unit,
    modifier: Modifier = Modifier,
    onOpen: ((LifeTask) -> Unit)? = null,
    showFocus: Boolean = false,
    onFocus: (() -> Unit)? = null,
) {
    val completed = task.status == TaskStatus.COMPLETED
    val expired = task.status == TaskStatus.EXPIRED || task.status == TaskStatus.SUPERSEDED
    val active = task.status.isActive

    Card(
        modifier = modifier
            .fillMaxWidth()
            .alpha(if (expired) 0.55f else 1f),
        shape = RoundedCornerShape(LookAfterDimens.radiusMD),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(
                    horizontal = LookAfterDimens.cardPadding,
                    vertical = LookAfterDimens.spacingSM,
                ),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingSM),
        ) {
            ConstraintBadge(constraintType = task.constraintType)

            Column(
                modifier = Modifier
                    .weight(1f)
                    .then(
                        if (onOpen != null && !completed && !expired) {
                            Modifier.clickable { onOpen(task) }
                        } else {
                            Modifier
                        },
                    ),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(
                    text = task.title,
                    style = MaterialTheme.typography.titleLarge,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    textDecoration = if (completed) TextDecoration.LineThrough else null,
                )
                Text(
                    text = metaLine(task),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            if (active && !expired) {
                // Start / pause toggle
                IconButton(
                    onClick = {
                        when (task.status) {
                            TaskStatus.IN_PROGRESS ->
                                onIntent(LookAfterIntent.UpdateTask(task.copy(status = TaskStatus.PAUSED)))
                            TaskStatus.PAUSED, TaskStatus.PENDING -> {
                                onIntent(LookAfterIntent.UpdateTask(task.copy(status = TaskStatus.IN_PROGRESS)))
                                onFocus?.invoke()
                            }
                            else -> Unit
                        }
                    },
                ) {
                    Icon(
                        imageVector = if (task.status == TaskStatus.IN_PROGRESS) {
                            Icons.Outlined.PauseCircle
                        } else {
                            Icons.Outlined.PlayCircle
                        },
                        contentDescription = if (task.status == TaskStatus.IN_PROGRESS) "Pause" else "Start",
                        tint = LookAfterColors.Focus,
                    )
                }
                IconButton(
                    onClick = {
                        onIntent(LookAfterIntent.ParkTask(task.id, reason = "today_snooze"))
                    },
                ) {
                    Icon(
                        Icons.Outlined.Snooze,
                        contentDescription = "Park",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            CompletionButton(
                completed = completed,
                enabled = !completed && !expired,
                onClick = { onIntent(LookAfterIntent.CompleteTask(task.id)) },
            )
        }
    }
}

@Composable
private fun ConstraintBadge(constraintType: ConstraintType) {
    val (label, tint) = when (constraintType) {
        ConstraintType.ANCHORED -> "A" to LookAfterColors.Anchored
        ConstraintType.FLEXIBLE -> "F" to LookAfterColors.Flexible
        ConstraintType.FLUID -> "·" to LookAfterColors.Fluid
    }
    Box(
        modifier = Modifier
            .size(36.dp)
            .clip(RoundedCornerShape(10.dp))
            .background(tint.copy(alpha = 0.12f)),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.titleLarge,
            color = tint,
        )
    }
}

@Composable
private fun CompletionButton(
    completed: Boolean,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    IconButton(onClick = onClick, enabled = enabled) {
        Icon(
            imageVector = if (completed) {
                Icons.Filled.CheckCircle
            } else {
                Icons.Outlined.RadioButtonUnchecked
            },
            contentDescription = if (completed) "Completed" else "Mark complete",
            tint = if (completed) LookAfterColors.Completed else MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(28.dp),
        )
    }
}

private val timeFmt: DateTimeFormatter = DateTimeFormatter.ofPattern("h:mm a")

private fun metaLine(task: LifeTask): String {
    val parts = mutableListOf("${task.durationMinutes} min")
    parts += when (task.constraintType) {
        ConstraintType.ANCHORED -> "Anchored"
        ConstraintType.FLEXIBLE -> "Flexible"
        ConstraintType.FLUID -> "Fluid"
    }
    task.scheduledStart?.let { start ->
        val z = start.atZone(ZoneId.systemDefault())
        parts += z.format(timeFmt)
    }
    if (task.priority == Priority.CRITICAL || task.priority == Priority.HIGH) {
        parts += task.priority.name.lowercase().replaceFirstChar { it.titlecase() }
    }
    if (task.recurrence != RecurrenceRule.NONE) {
        parts += task.recurrence.label
    }
    if (task.status == TaskStatus.IN_PROGRESS) parts += "Live"
    if (task.status == TaskStatus.PAUSED) parts += "Paused"
    if (task.status != TaskStatus.PENDING &&
        task.status != TaskStatus.IN_PROGRESS &&
        task.status != TaskStatus.PAUSED
    ) {
        parts += task.status.name.lowercase().replaceFirstChar { it.titlecase() }
    }
    return parts.joinToString(" · ")
}
