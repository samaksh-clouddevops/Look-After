package com.lookafter.app.ui.tasks

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import com.lookafter.app.ui.theme.LookAfterColors
import com.lookafter.app.ui.theme.LookAfterDimens
import com.lookafter.core.engine.LookAfterIntent
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.Priority
import com.lookafter.core.models.RecurrenceRule
import com.lookafter.core.models.TaskExpirationPolicy
import com.lookafter.core.models.TaskStatus
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.util.UUID

/**
 * Full create / edit sheet — title, duration, constraint, priority, recurrence, notes.
 * Mirrors the iOS task form surface used from Capture + Today.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TaskEditorSheet(
    currentDay: LocalDate?,
    existing: LifeTask? = null,
    onIntent: (LookAfterIntent) -> Unit,
    onDismiss: () -> Unit,
    onDelete: ((LifeTask) -> Unit)? = null,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val editing = existing != null
    var title by remember(existing?.id) { mutableStateOf(existing?.title.orEmpty()) }
    var notes by remember(existing?.id) { mutableStateOf(existing?.notes.orEmpty()) }
    var minutesText by remember(existing?.id) {
        mutableStateOf((existing?.durationMinutes ?: 30).toString())
    }
    var constraint by remember(existing?.id) {
        mutableStateOf(existing?.constraintType ?: ConstraintType.FLEXIBLE)
    }
    var priority by remember(existing?.id) {
        mutableStateOf(existing?.priority ?: Priority.MEDIUM)
    }
    var recurrence by remember(existing?.id) {
        mutableStateOf(existing?.recurrence ?: RecurrenceRule.NONE)
    }
    // Simple wall-clock hour for optional schedule (empty = unscheduled flexible/fluid).
    var hourText by remember(existing?.id) {
        val h = existing?.scheduledStart
            ?.atZone(ZoneId.systemDefault())
            ?.hour
        mutableStateOf(h?.toString().orEmpty())
    }
    var minuteOfDayText by remember(existing?.id) {
        val m = existing?.scheduledStart
            ?.atZone(ZoneId.systemDefault())
            ?.minute
        mutableStateOf(m?.toString()?.padStart(2, '0').orEmpty())
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = MaterialTheme.colorScheme.surface,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = LookAfterDimens.screenHorizontal)
                .padding(bottom = LookAfterDimens.spacingXL)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingMD),
        ) {
            Text(
                text = if (editing) "Edit task" else "New task",
                style = MaterialTheme.typography.headlineMedium,
            )
            OutlinedTextField(
                value = title,
                onValueChange = { title = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Title") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
            )
            OutlinedTextField(
                value = notes,
                onValueChange = { notes = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Notes (optional)") },
                minLines = 2,
                maxLines = 4,
            )
            OutlinedTextField(
                value = minutesText,
                onValueChange = { minutesText = it.filter(Char::isDigit).take(3) },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Duration (minutes)") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            )

            ChipSection(label = "Constraint") {
                ConstraintType.entries.forEach { c ->
                    FilterChip(
                        selected = constraint == c,
                        onClick = { constraint = c },
                        label = { Text(c.name.lowercase().replaceFirstChar { it.titlecase() }) },
                        colors = chipColors(),
                    )
                }
            }
            ChipSection(label = "Priority") {
                listOf(Priority.CRITICAL, Priority.HIGH, Priority.MEDIUM, Priority.LOW, Priority.SOMEDAY)
                    .forEach { p ->
                        FilterChip(
                            selected = priority == p,
                            onClick = { priority = p },
                            label = { Text(p.name.lowercase().replaceFirstChar { it.titlecase() }) },
                            colors = chipColors(),
                        )
                    }
            }
            ChipSection(label = "Repeats") {
                RecurrenceRule.entries.forEach { r ->
                    FilterChip(
                        selected = recurrence == r,
                        onClick = { recurrence = r },
                        label = { Text(r.label) },
                        colors = chipColors(),
                    )
                }
            }

            Text("Start time (optional)", style = MaterialTheme.typography.labelMedium)
            Row(horizontalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingSM)) {
                OutlinedTextField(
                    value = hourText,
                    onValueChange = { hourText = it.filter(Char::isDigit).take(2) },
                    modifier = Modifier.weight(1f),
                    label = { Text("Hour") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                )
                OutlinedTextField(
                    value = minuteOfDayText,
                    onValueChange = { minuteOfDayText = it.filter(Char::isDigit).take(2) },
                    modifier = Modifier.weight(1f),
                    label = { Text("Min") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingSM),
            ) {
                TextButton(onClick = onDismiss, modifier = Modifier.weight(1f)) { Text("Cancel") }
                if (editing && existing != null && onDelete != null) {
                    TextButton(
                        onClick = {
                            onDelete(existing)
                            onDismiss()
                        },
                        modifier = Modifier.weight(1f),
                    ) { Text("Delete") }
                }
                Button(
                    onClick = {
                        val trimmed = title.trim()
                        if (trimmed.isEmpty()) return@Button
                        val minutes = minutesText.toIntOrNull()?.coerceIn(5, 480) ?: 30
                        val day = currentDay ?: LocalDate.now()
                        val now = Instant.now()
                        val zone = ZoneId.systemDefault()
                        val start = parseStart(day, hourText, minuteOfDayText, zone)
                        val end = start?.plusSeconds(minutes * 60L)
                        val task = (existing ?: LifeTask(
                            id = "task-" + UUID.randomUUID(),
                            title = trimmed,
                            status = TaskStatus.PENDING,
                            createdAt = now,
                        )).copy(
                            title = trimmed,
                            notes = notes.trim(),
                            durationMinutes = minutes,
                            constraintType = constraint,
                            priority = priority,
                            recurrence = recurrence,
                            scheduledDate = day,
                            scheduledStart = start,
                            scheduledEnd = end,
                            expirationPolicy = when (constraint) {
                                ConstraintType.ANCHORED -> TaskExpirationPolicy.EndOfDay
                                ConstraintType.FLUID -> TaskExpirationPolicy.EndOfDay
                                ConstraintType.FLEXIBLE -> TaskExpirationPolicy.Infinite
                            },
                            updatedAt = now,
                            tags = mergeTags(existing?.tags.orEmpty(), editing),
                        )
                        onIntent(
                            if (editing) LookAfterIntent.UpdateTask(task)
                            else LookAfterIntent.AddTask(task),
                        )
                        onDismiss()
                    },
                    modifier = Modifier.weight(1f),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = LookAfterColors.AccentPrimary,
                        contentColor = LookAfterColors.AccentOnPrimary,
                    ),
                    enabled = title.trim().isNotEmpty(),
                ) { Text(if (editing) "Save" else "Add") }
            }
        }
    }
}

@Composable
private fun ChipSection(
    label: String,
    content: @Composable androidx.compose.foundation.layout.RowScope.() -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingXS)) {
        Text(label, style = MaterialTheme.typography.labelMedium)
        Row(
            modifier = Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingXS),
            content = content,
        )
    }
}

@Composable
private fun chipColors() = FilterChipDefaults.filterChipColors(
    selectedContainerColor = LookAfterColors.AccentSoft,
    selectedLabelColor = LookAfterColors.AccentPrimary,
)

private fun parseStart(
    day: LocalDate,
    hourText: String,
    minuteText: String,
    zone: ZoneId,
): Instant? {
    val h = hourText.toIntOrNull() ?: return null
    if (h !in 0..23) return null
    val m = minuteText.toIntOrNull()?.coerceIn(0, 59) ?: 0
    return day.atTime(LocalTime.of(h, m)).atZone(zone).toInstant()
}

private fun mergeTags(existing: List<String>, editing: Boolean): List<String> {
    if (editing) return existing
    return (existing + "manual").distinct()
}
