package com.lookafter.app.ui.capture

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
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
import com.lookafter.core.models.TaskExpirationPolicy
import com.lookafter.core.models.TaskStatus
import java.time.LocalDate
import java.util.UUID

/**
 * Capture sheet — iOS quick-capture parity.
 * Creates a fluid inbox-style task via [LookAfterIntent.AddTask].
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CaptureSheet(
    currentDay: LocalDate?,
    onIntent: (LookAfterIntent) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var title by remember { mutableStateOf("") }
    var minutesText by remember { mutableStateOf("15") }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = MaterialTheme.colorScheme.surface,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = LookAfterDimens.screenHorizontal)
                .padding(bottom = LookAfterDimens.spacingXL),
            verticalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingMD),
        ) {
            Text(
                text = "Capture",
                style = MaterialTheme.typography.headlineMedium,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                text = "Park a thought as fluid work. Schedule it later on Today.",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            OutlinedTextField(
                value = title,
                onValueChange = { title = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("What's on your mind?") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.Sentences,
                ),
            )
            OutlinedTextField(
                value = minutesText,
                onValueChange = { minutesText = it.filter { ch -> ch.isDigit() }.take(3) },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Minutes") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingSM),
            ) {
                TextButton(
                    onClick = onDismiss,
                    modifier = Modifier.weight(1f),
                ) { Text("Cancel") }
                Button(
                    onClick = {
                        val trimmed = title.trim()
                        if (trimmed.isEmpty()) return@Button
                        val minutes = minutesText.toIntOrNull()?.coerceIn(5, 480) ?: 15
                        onIntent(
                            LookAfterIntent.AddTask(
                                LifeTask(
                                    id = "cap-" + UUID.randomUUID(),
                                    title = trimmed,
                                    durationMinutes = minutes,
                                    constraintType = ConstraintType.FLUID,
                                    status = TaskStatus.PENDING,
                                    expirationPolicy = TaskExpirationPolicy.EndOfDay,
                                    scheduledDate = currentDay ?: LocalDate.now(),
                                    tags = listOf("capture"),
                                ),
                            ),
                        )
                        onDismiss()
                    },
                    modifier = Modifier.weight(1f),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = LookAfterColors.AccentPrimary,
                        contentColor = LookAfterColors.AccentOnPrimary,
                    ),
                    enabled = title.trim().isNotEmpty(),
                ) { Text("Save") }
            }
        }
    }
}
