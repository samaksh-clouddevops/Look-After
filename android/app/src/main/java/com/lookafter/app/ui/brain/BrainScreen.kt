package com.lookafter.app.ui.brain

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.lookafter.app.ui.components.ElevatedSurfaceCard
import com.lookafter.app.ui.components.SectionHeader
import com.lookafter.app.ui.theme.LookAfterColors
import com.lookafter.app.ui.theme.LookAfterDimens
import com.lookafter.core.brain.BrainTick
import com.lookafter.core.brain.CognitiveLoadLevel

@Composable
fun BrainScreen(
    tick: BrainTick,
    coachTranscript: List<Pair<Boolean, String>>,
    onSendCoach: (String) -> Unit,
    onStartFocus: () -> Unit,
    onEmergencyFocus: () -> Unit = onStartFocus,
    modifier: Modifier = Modifier,
) {
    var draft by remember { mutableStateOf("") }
    val world = tick.world
    val decision = tick.decision

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(
            horizontal = LookAfterDimens.screenHorizontal,
            vertical = LookAfterDimens.spacingLG,
        ),
        verticalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingMD),
    ) {
        item { SectionHeader(title = "Brain", subtitle = "One next move. No noise.") }
        item {
            ElevatedSurfaceCard {
                Text("Hero", style = MaterialTheme.typography.labelMedium, color = LookAfterColors.AccentPrimary)
                Text(decision.heroTitle, style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(top = LookAfterDimens.spacingXXS))
                Text(decision.reason, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = LookAfterDimens.spacingXS))
                Text(decision.coachLine, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = LookAfterDimens.spacingXS))
                Button(
                    onClick = onStartFocus,
                    modifier = Modifier.fillMaxWidth().padding(top = LookAfterDimens.spacingSM),
                    colors = ButtonDefaults.buttonColors(containerColor = LookAfterColors.AccentPrimary, contentColor = LookAfterColors.AccentOnPrimary),
                ) { Text(decision.actionLabel) }
                Button(
                    onClick = onEmergencyFocus,
                    modifier = Modifier.fillMaxWidth().padding(top = LookAfterDimens.spacingXS),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = LookAfterColors.Warning,
                        contentColor = LookAfterColors.LightTextPrimary,
                    ),
                ) { Text("Emergency 10-min focus") }
            }
        }
        item {
            ElevatedSurfaceCard {
                Text("World", style = MaterialTheme.typography.labelMedium, color = LookAfterColors.AccentPrimary)
                Text(
                    "Energy " + "%.0f".format(world.currentEnergy * 100) + "% · Load " + world.cognitiveLoad.name.lowercase() + " · Open " + world.openTaskCount,
                    style = MaterialTheme.typography.titleLarge,
                    modifier = Modifier.padding(top = LookAfterDimens.spacingXXS),
                )
                if (world.cognitiveLoad == CognitiveLoadLevel.OVERLOADED) {
                    Text("Overloaded — strip to one block.", color = LookAfterColors.Warning, style = MaterialTheme.typography.labelMedium, modifier = Modifier.padding(top = LookAfterDimens.spacingXS))
                }
            }
        }
        item { Text("Coach", style = MaterialTheme.typography.titleMedium) }
        items(coachTranscript) { pair ->
            val isUser = pair.first
            val line = pair.second
            ElevatedSurfaceCard {
                Text(if (isUser) "You" else "Look After", style = MaterialTheme.typography.labelMedium, color = if (isUser) MaterialTheme.colorScheme.onSurfaceVariant else LookAfterColors.AccentPrimary)
                Text(line, style = MaterialTheme.typography.bodyLarge)
            }
        }
        item {
            Column(verticalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingSM)) {
                OutlinedTextField(
                    value = draft,
                    onValueChange = { draft = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Ask the coach") },
                    singleLine = true,
                )
                Row {
                    Button(
                        onClick = { onSendCoach(draft); draft = "" },
                        enabled = draft.trim().isNotEmpty(),
                        colors = ButtonDefaults.buttonColors(containerColor = LookAfterColors.AccentPrimary),
                    ) { Text("Send") }
                }
            }
        }
    }
}
