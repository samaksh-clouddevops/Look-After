package com.lookafter.app.ui.inbox

import androidx.compose.foundation.clickable
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
import androidx.compose.material3.TextButton
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
import com.lookafter.core.inbox.InboxIntent
import com.lookafter.core.inbox.InboxState

@Composable
fun InboxScreen(
    state: InboxState,
    onIntent: (InboxIntent) -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var draft by remember { mutableStateOf("") }
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(
            horizontal = LookAfterDimens.screenHorizontal,
            vertical = LookAfterDimens.spacingLG,
        ),
        verticalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingSM),
    ) {
        item {
            SectionHeader(
                title = "Inbox",
                subtitle = "Park thoughts. Promote when ready.",
            )
        }
        item {
            OutlinedTextField(
                value = draft,
                onValueChange = { draft = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Quick capture") },
                singleLine = true,
            )
            Button(
                onClick = {
                    onIntent(InboxIntent.Capture(draft))
                    draft = ""
                },
                enabled = draft.trim().isNotEmpty(),
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = LookAfterDimens.spacingSM),
                colors = ButtonDefaults.buttonColors(
                    containerColor = LookAfterColors.AccentPrimary,
                    contentColor = LookAfterColors.AccentOnPrimary,
                ),
            ) { Text("Add") }
        }
        if (state.open.isEmpty()) {
            item {
                ElevatedSurfaceCard {
                    Text("Inbox zero", style = MaterialTheme.typography.titleLarge)
                    Text(
                        "Capture from here or the center + button.",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        } else {
            items(state.open, key = { it.id }) { item ->
                ElevatedSurfaceCard {
                    Text(item.text, style = MaterialTheme.typography.titleLarge)
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = LookAfterDimens.spacingSM),
                        horizontalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingSM),
                    ) {
                        TextButton(onClick = { onIntent(InboxIntent.PromoteToTask(item.id)) }) {
                            Text("To Today")
                        }
                        TextButton(onClick = { onIntent(InboxIntent.Discard(item.id)) }) {
                            Text("Discard")
                        }
                    }
                }
            }
        }
        item {
            Text(
                "Back",
                color = LookAfterColors.AccentPrimary,
                modifier = Modifier
                    .clickable(onClick = onBack)
                    .padding(top = LookAfterDimens.spacingMD),
            )
        }
    }
}
