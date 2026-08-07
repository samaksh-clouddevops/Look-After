package com.lookafter.app.ui.brain

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.lookafter.app.ui.components.ElevatedSurfaceCard
import com.lookafter.app.ui.components.SectionHeader
import com.lookafter.app.ui.theme.LookAfterColors
import com.lookafter.app.ui.theme.LookAfterDimens
import com.lookafter.core.brain.HeroTaskRanker
import com.lookafter.core.engine.LifeState
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.TaskStatus

/** Executive Brain surface — calm decision feed (iOS Brain tab parity). */
@Composable
fun BrainScreen(
    state: LifeState,
    modifier: Modifier = Modifier,
) {
    val selection = HeroTaskRanker.select(state)
    val hero = selection.task
    val parked = state.parkedQueue.size
    val anchored = state.activeTasks.count {
        it.status.isActive && it.constraintType == ConstraintType.ANCHORED
    }

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
                title = "Brain",
                subtitle = "One next move. No noise.",
            )
        }
        item {
            ElevatedSurfaceCard {
                Text(
                    text = "Hero",
                    style = MaterialTheme.typography.labelMedium,
                    color = LookAfterColors.AccentPrimary,
                )
                Text(
                    text = hero?.title ?: "Nothing queued — enjoy the space.",
                    style = MaterialTheme.typography.titleLarge,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.padding(top = LookAfterDimens.spacingXXS),
                )
                Text(
                    text = selection.reason,
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
                )
                if (hero != null) {
                    Text(
                        text = "${hero.durationMinutes} min · ${hero.constraintType.name.lowercase()}",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = LookAfterDimens.spacingXXS),
                    )
                }
            }
        }
        item {
            ElevatedSurfaceCard {
                Text(
                    text = "Load",
                    style = MaterialTheme.typography.labelMedium,
                    color = LookAfterColors.AccentPrimary,
                )
                Text(
                    text = "$anchored anchored · $parked parked · " +
                        "${state.activeTasks.count { it.status == TaskStatus.COMPLETED }} complete",
                    style = MaterialTheme.typography.titleLarge,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.padding(top = LookAfterDimens.spacingXXS),
                )
                Text(
                    text = "Brain surfaces orientation only. Mutations flow through Today intents.",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
                )
            }
        }
        item {
            ElevatedSurfaceCard {
                Text(
                    text = "Coach",
                    style = MaterialTheme.typography.labelMedium,
                    color = LookAfterColors.AccentPrimary,
                )
                Text(
                    text = "Protect deep work. Batch fluid tasks. " +
                        "Never invent medication times outside your inventory.",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = LookAfterDimens.spacingXXS),
                )
            }
        }
    }
}
