package com.lookafter.app.ui.medication

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import com.lookafter.app.ui.components.ElevatedSurfaceCard
import com.lookafter.app.ui.components.SectionHeader
import com.lookafter.app.ui.theme.LookAfterColors
import com.lookafter.app.ui.theme.LookAfterDimens
import com.lookafter.core.engine.LifeState
import com.lookafter.core.engine.LookAfterIntent
import com.lookafter.core.models.Medication
import java.time.LocalDate
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import kotlin.math.roundToInt

/** Medication inventory — iOS MedicationView parity on LifeEngine. */
@Composable
fun MedicationScreen(
    state: LifeState,
    onIntent: (LookAfterIntent) -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    LaunchedEffect(Unit) {
        onIntent(LookAfterIntent.ResetMedicationsForNewDay(LocalDate.now()))
    }

    val meds = state.medications
    val adherencePct = (state.medicationAdherenceRate * 100).roundToInt()
    val timeFmt = DateTimeFormatter.ofPattern("h:mm a")

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(
            horizontal = LookAfterDimens.screenHorizontal,
            vertical = LookAfterDimens.spacingLG,
        ),
        verticalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingSM),
    ) {
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top,
            ) {
                SectionHeader(
                    title = "Medication",
                    subtitle = "Track daily routines and adherence.",
                    modifier = Modifier.weight(1f),
                )
                IconButton(
                    onClick = {
                        onIntent(
                            LookAfterIntent.AddMedication(
                                Medication(
                                    name = "New medication",
                                    dosage = "1 dose",
                                    scheduledTime = LocalTime.of(9, 0),
                                ),
                            ),
                        )
                    },
                ) {
                    Icon(
                        Icons.Filled.AddCircle,
                        contentDescription = "Add medication",
                        tint = LookAfterColors.AccentPrimary,
                        modifier = Modifier.size(28.dp),
                    )
                }
            }
        }
        if (meds.isNotEmpty()) {
            item {
                Text(
                    text = "Today's Adherence: $adherencePct%",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        if (meds.isEmpty()) {
            item {
                ElevatedSurfaceCard {
                    Text("No Medications Tracked", style = MaterialTheme.typography.titleLarge)
                    Text(
                        "Add your daily medications or supplements to track adherence.",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
                    )
                }
            }
        } else {
            items(meds, key = { it.id }) { med ->
                MedicationRow(
                    med = med,
                    timeLabel = med.scheduledTime.format(timeFmt),
                    onToggle = {
                        onIntent(
                            LookAfterIntent.TakeMedication(id = med.id, taken = !med.isTaken),
                        )
                    },
                    onDelete = { onIntent(LookAfterIntent.DeleteMedication(med.id)) },
                )
            }
        }
        item {
            Text(
                text = "Back",
                style = MaterialTheme.typography.labelMedium,
                color = LookAfterColors.AccentPrimary,
                modifier = Modifier
                    .clickable(onClick = onBack)
                    .padding(top = LookAfterDimens.spacingMD),
            )
        }
    }
}

@Composable
private fun MedicationRow(
    med: Medication,
    timeLabel: String,
    onToggle: () -> Unit,
    onDelete: () -> Unit,
) {
    ElevatedSurfaceCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingSM),
        ) {
            IconButton(onClick = onToggle) {
                Icon(
                    imageVector = if (med.isTaken) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
                    contentDescription = if (med.isTaken) "Taken" else "Mark taken",
                    tint = if (med.isTaken) LookAfterColors.Success else MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(24.dp),
                )
            }
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = med.name,
                    style = MaterialTheme.typography.titleLarge,
                    color = if (med.isTaken) {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    } else {
                        MaterialTheme.colorScheme.onSurface
                    },
                    textDecoration = if (med.isTaken) TextDecoration.LineThrough else null,
                )
                Text(
                    text = "${med.dosage} · $timeLabel",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (med.adherenceLog.isNotEmpty()) {
                    Text(
                        text = "Taken ${med.adherenceLog.size} times",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            IconButton(onClick = onDelete) {
                Icon(Icons.Outlined.Delete, contentDescription = "Delete", tint = LookAfterColors.Error)
            }
        }
    }
}
