package com.lookafter.app.ui.creativity

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
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
import com.lookafter.app.ui.components.CalmEmptyState
import com.lookafter.app.ui.components.ElevatedSurfaceCard
import com.lookafter.app.ui.components.SectionHeader
import com.lookafter.app.ui.theme.LookAfterColors
import com.lookafter.app.ui.theme.LookAfterDimens
import com.lookafter.core.creativity.CreativeBoard
import com.lookafter.core.creativity.CreativeSpark
import com.lookafter.core.creativity.CreativeSparkKind
import com.lookafter.core.creativity.CreativityState
import java.time.Instant

/** Creativity boards scaffold (Phase E4). */
@Composable
fun CreativityScreen(
    state: CreativityState,
    onAddBoard: (CreativeBoard) -> Unit,
    onSelectBoard: (String?) -> Unit,
    onDeleteBoard: (String) -> Unit,
    onAddSpark: (CreativeSpark, boardId: String?) -> Unit,
    onDeleteSpark: (String) -> Unit,
    onPinSpark: (id: String, pinned: Boolean) -> Unit,
    onPromoteToCapture: (sparkId: String) -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var boardTitle by remember { mutableStateOf("") }
    var sparkTitle by remember { mutableStateOf("") }
    var sparkBody by remember { mutableStateOf("") }
    var sparkKind by remember { mutableStateOf(CreativeSparkKind.IDEA) }
    val selected = state.selectedBoard
    val sparks = selected?.let { state.sparksForBoard(it.id) }.orEmpty()
        .sortedWith(compareByDescending<CreativeSpark> { it.pinned }.thenByDescending { it.updatedAt })

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(
            horizontal = LookAfterDimens.screenHorizontal,
            vertical = LookAfterDimens.spacingLG,
        ),
        verticalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingMD),
    ) {
        item {
            SectionHeader(
                title = "Creativity",
                subtitle = "Boards of sparks — promote to Capture when ready",
            )
        }
        item {
            ElevatedSurfaceCard {
                Text("Boards", style = MaterialTheme.typography.labelMedium, color = LookAfterColors.AccentPrimary)
                Row(
                    Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState())
                        .padding(top = LookAfterDimens.spacingSM),
                    horizontalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingXS),
                ) {
                    state.boards.forEach { board ->
                        FilterChip(
                            selected = board.id == selected?.id,
                            onClick = { onSelectBoard(board.id) },
                            label = { Text("${board.title} · ${board.sparkCount}") },
                            colors = FilterChipDefaults.filterChipColors(
                                selectedContainerColor = LookAfterColors.AccentSoft,
                                selectedLabelColor = LookAfterColors.AccentPrimary,
                            ),
                        )
                    }
                }
                OutlinedTextField(
                    value = boardTitle,
                    onValueChange = { boardTitle = it },
                    modifier = Modifier.fillMaxWidth().padding(top = LookAfterDimens.spacingSM),
                    label = { Text("New board title") },
                    singleLine = true,
                )
                Row(
                    Modifier.fillMaxWidth().padding(top = LookAfterDimens.spacingSM),
                    horizontalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingSM),
                ) {
                    Button(
                        onClick = {
                            val t = boardTitle.trim()
                            if (t.isNotEmpty()) {
                                onAddBoard(CreativeBoard(title = t, createdAt = Instant.now()))
                                boardTitle = ""
                            }
                        },
                        enabled = boardTitle.isNotBlank(),
                        colors = ButtonDefaults.buttonColors(containerColor = LookAfterColors.AccentPrimary),
                    ) { Text("Add board") }
                    if (selected != null && state.boards.size > 1) {
                        TextButton(onClick = { onDeleteBoard(selected.id) }) { Text("Delete board") }
                    }
                }
            }
        }
        item {
            ElevatedSurfaceCard {
                Text("New spark", style = MaterialTheme.typography.labelMedium, color = LookAfterColors.Focus)
                Row(
                    Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState())
                        .padding(top = LookAfterDimens.spacingSM),
                    horizontalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingXS),
                ) {
                    CreativeSparkKind.entries.forEach { k ->
                        FilterChip(
                            selected = sparkKind == k,
                            onClick = { sparkKind = k },
                            label = { Text(k.label) },
                            colors = FilterChipDefaults.filterChipColors(
                                selectedContainerColor = LookAfterColors.AccentSoft,
                                selectedLabelColor = LookAfterColors.AccentPrimary,
                            ),
                        )
                    }
                }
                OutlinedTextField(
                    value = sparkTitle,
                    onValueChange = { sparkTitle = it },
                    modifier = Modifier.fillMaxWidth().padding(top = LookAfterDimens.spacingSM),
                    label = { Text("Title") },
                    singleLine = true,
                )
                OutlinedTextField(
                    value = sparkBody,
                    onValueChange = { sparkBody = it },
                    modifier = Modifier.fillMaxWidth().padding(top = LookAfterDimens.spacingSM),
                    label = { Text("Body") },
                    minLines = 2,
                )
                Button(
                    onClick = {
                        if (sparkTitle.isBlank() && sparkBody.isBlank()) return@Button
                        onAddSpark(
                            CreativeSpark(
                                title = sparkTitle.trim().ifBlank { sparkKind.label },
                                body = sparkBody.trim(),
                                kind = sparkKind,
                                createdAt = Instant.now(),
                            ),
                            selected?.id,
                        )
                        sparkTitle = ""
                        sparkBody = ""
                    },
                    modifier = Modifier.padding(top = LookAfterDimens.spacingSM),
                    colors = ButtonDefaults.buttonColors(containerColor = LookAfterColors.AccentPrimary),
                ) { Text("Add to ${selected?.title ?: "inbox"}") }
            }
        }
        if (sparks.isEmpty()) {
            item {
                CalmEmptyState(
                    title = "Quiet board",
                    subtitle = "Drop an idea, question, or snippet. Promote one to Capture when it wants a home on Today.",
                )
            }
        } else {
            items(sparks, key = { it.id }) { spark ->
                ElevatedSurfaceCard {
                    Text(
                        spark.kind.label + if (spark.pinned) " · pinned" else "",
                        style = MaterialTheme.typography.labelMedium,
                        color = LookAfterColors.AccentPrimary,
                    )
                    Text(spark.title, style = MaterialTheme.typography.titleLarge)
                    if (spark.body.isNotBlank()) {
                        Text(
                            spark.body,
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(top = LookAfterDimens.spacingXXS),
                        )
                    }
                    Row(
                        Modifier.fillMaxWidth().padding(top = LookAfterDimens.spacingSM),
                        horizontalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingSM),
                    ) {
                        TextButton(onClick = { onPinSpark(spark.id, !spark.pinned) }) {
                            Text(if (spark.pinned) "Unpin" else "Pin")
                        }
                        TextButton(onClick = { onPromoteToCapture(spark.id) }) { Text("→ Capture") }
                        TextButton(onClick = { onDeleteSpark(spark.id) }) { Text("Delete") }
                    }
                }
            }
        }
        item {
            Text(
                "Back",
                color = LookAfterColors.AccentPrimary,
                modifier = Modifier.clickable(onClick = onBack).padding(top = LookAfterDimens.spacingSM),
            )
        }
    }
}
