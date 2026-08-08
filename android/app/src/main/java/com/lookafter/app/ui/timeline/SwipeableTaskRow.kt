package com.lookafter.app.ui.timeline

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Snooze
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.lookafter.app.ui.theme.LookAfterColors
import com.lookafter.app.ui.theme.LookAfterDimens
import com.lookafter.core.engine.LookAfterIntent
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.TaskStatus

/**
 * Swipe right → complete · Swipe left → park.
 * Uses Material3 [SwipeToDismissBox].
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SwipeableTaskRow(
    task: LifeTask,
    onIntent: (LookAfterIntent) -> Unit,
    onOpen: ((LifeTask) -> Unit)? = null,
    onFocus: (() -> Unit)? = null,
    showFocus: Boolean = false,
    enabled: Boolean = true,
    modifier: Modifier = Modifier,
) {
    if (!enabled || !task.status.isActive) {
        TimelineTaskCard(
            task = task,
            onIntent = onIntent,
            onOpen = onOpen,
            showFocus = showFocus,
            onFocus = onFocus,
            modifier = modifier,
        )
        return
    }

    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            when (value) {
                SwipeToDismissBoxValue.StartToEnd -> {
                    onIntent(LookAfterIntent.CompleteTask(task.id))
                    true
                }
                SwipeToDismissBoxValue.EndToStart -> {
                    onIntent(LookAfterIntent.ParkTask(task.id, reason = "swipe_park"))
                    true
                }
                SwipeToDismissBoxValue.Settled -> false
            }
        },
        positionalThreshold = { it * 0.35f },
    )

    SwipeToDismissBox(
        state = dismissState,
        modifier = modifier.fillMaxWidth(),
        backgroundContent = {
            val direction = dismissState.dismissDirection
            val color by animateColorAsState(
                targetValue = when (direction) {
                    SwipeToDismissBoxValue.StartToEnd -> LookAfterColors.Success
                    SwipeToDismissBoxValue.EndToStart -> LookAfterColors.Warning
                    else -> Color.Transparent
                },
                label = "swipe-bg",
            )
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .clip(RoundedCornerShape(LookAfterDimens.radiusMD))
                    .background(color)
                    .padding(horizontal = LookAfterDimens.cardPadding),
                contentAlignment = when (direction) {
                    SwipeToDismissBoxValue.StartToEnd -> Alignment.CenterStart
                    SwipeToDismissBoxValue.EndToStart -> Alignment.CenterEnd
                    else -> Alignment.Center
                },
            ) {
                when (direction) {
                    SwipeToDismissBoxValue.StartToEnd -> {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Outlined.CheckCircle, contentDescription = null, tint = Color.White)
                            Spacer(Modifier.padding(4.dp))
                            Text("Complete", color = Color.White)
                        }
                    }
                    SwipeToDismissBoxValue.EndToStart -> {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("Park", color = Color.White)
                            Spacer(Modifier.padding(4.dp))
                            Icon(Icons.Outlined.Snooze, contentDescription = null, tint = Color.White)
                        }
                    }
                    else -> Unit
                }
            }
        },
        content = {
            TimelineTaskCard(
                task = task,
                onIntent = onIntent,
                onOpen = onOpen,
                showFocus = showFocus,
                onFocus = onFocus,
            )
        },
    )
}
