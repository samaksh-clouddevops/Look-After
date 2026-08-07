package com.lookafter.app.ui.timeline

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.outlined.DoNotDisturbOn
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.compose.material.icons.outlined.SelfImprovement
import com.lookafter.app.execution.SystemFocusController
import com.lookafter.app.ui.components.CalmEmptyState
import com.lookafter.app.ui.components.ElevatedSurfaceCard
import com.lookafter.app.ui.components.SectionHeader
import com.lookafter.app.ui.theme.LookAfterColors
import com.lookafter.app.ui.theme.LookAfterDimens
import com.lookafter.core.engine.LifeState
import com.lookafter.core.engine.LookAfterIntent
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.TaskStatus
import java.time.LocalDate
import java.time.format.DateTimeFormatter

/**
 * Primary Today surface — hero card + timeline of active tasks (iOS Today parity).
 */
@Composable
fun TodayTimelineScreen(
    state: LifeState,
    onIntent: (LookAfterIntent) -> Unit,
    modifier: Modifier = Modifier,
    restoredFromDisk: Boolean = false,
    hydrationComplete: Boolean = true,
    heroTitle: String? = null,
    heroReason: String? = null,
    onStartFocus: (() -> Unit)? = null,
    onOpenTask: ((LifeTask) -> Unit)? = null,
    onCreateTask: (() -> Unit)? = null,
) {
    val context = LocalContext.current
    val policyGrantedState = remember {
        mutableStateOf(SystemFocusController.isPolicyAccessGranted(context))
    }
    // Re-check when returning from system settings.
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        policyGrantedState.value = SystemFocusController.isPolicyAccessGranted(context)
    }
    val policyGranted by policyGrantedState

    // Prefer still-actionable work; completed stay visible for the session.
    val tasks = state.activeTasks
        .sortedWith(
            compareBy<com.lookafter.core.models.LifeTask> {
                when (it.status) {
                    TaskStatus.COMPLETED, TaskStatus.EXPIRED, TaskStatus.SUPERSEDED -> 1
                    else -> 0
                }
            }.thenBy { it.scheduledStart ?: java.time.Instant.MAX },
        )

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(
            horizontal = LookAfterDimens.screenHorizontal,
            vertical = LookAfterDimens.spacingLG,
        ),
        verticalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingSM),
    ) {
        item(key = "header") {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = LookAfterDimens.spacingXS),
                verticalAlignment = Alignment.Top,
            ) {
                SectionHeader(
                    title = "Today",
                    subtitle = subtitle(state, restoredFromDisk, hydrationComplete),
                    modifier = Modifier.weight(1f),
                )
                if (onCreateTask != null) {
                    IconButton(onClick = onCreateTask) {
                        Icon(
                            Icons.Filled.Add,
                            contentDescription = "New task",
                            tint = LookAfterColors.AccentPrimary,
                        )
                    }
                }
            }
        }

        if (!heroTitle.isNullOrBlank()) {
            item(key = "hero") {
                ElevatedSurfaceCard(
                    modifier = if (onStartFocus != null) {
                        Modifier.clickable(onClick = onStartFocus)
                    } else {
                        Modifier
                    },
                ) {
                    Text(
                        text = "Next up",
                        style = MaterialTheme.typography.labelMedium,
                        color = LookAfterColors.AccentPrimary,
                    )
                    Text(
                        text = heroTitle,
                        style = MaterialTheme.typography.titleLarge,
                        color = MaterialTheme.colorScheme.onSurface,
                        modifier = Modifier.padding(top = LookAfterDimens.spacingXXS),
                    )
                    if (!heroReason.isNullOrBlank()) {
                        Text(
                            text = heroReason,
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
                        )
                    }
                    if (onStartFocus != null) {
                        Text(
                            text = "Tap to begin focus",
                            style = MaterialTheme.typography.labelMedium,
                            color = LookAfterColors.AccentPrimary,
                            modifier = Modifier.padding(top = LookAfterDimens.spacingSM),
                        )
                    }
                }
            }
        }

        if (!policyGranted) {
            item(key = "strict-focus-banner") {
                StrictFocusPermissionBanner(
                    onEnableClick = {
                        context.startActivity(
                            SystemFocusController.notificationPolicySettingsIntent(),
                        )
                    },
                )
            }
        }

        if (tasks.isEmpty()) {
            item(key = "empty") {
                CalmEmptyState(
                    title = "Equilibrium achieved",
                    subtitle = "No active work on the board. Protect the quiet — or capture the next intentional block.",
                    icon = Icons.Outlined.SelfImprovement,
                    actionLabel = if (onCreateTask != null) "New task" else null,
                    onAction = onCreateTask,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 48.dp),
                )
            }
        } else {
            items(tasks, key = { it.id }) { task ->
                TimelineTaskCard(
                    task = task,
                    onIntent = onIntent,
                    onOpen = onOpenTask,
                )
            }
        }
    }
}

@Composable
private fun StrictFocusPermissionBanner(
    onEnableClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Card(
        modifier = modifier
            .fillMaxWidth()
            .clickable(onClick = onEnableClick),
        shape = RoundedCornerShape(14.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.primaryContainer,
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(
                imageVector = Icons.Outlined.DoNotDisturbOn,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onPrimaryContainer,
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "Enable Strict Focus",
                    style = MaterialTheme.typography.titleLarge,
                    color = MaterialTheme.colorScheme.onPrimaryContainer,
                )
                Text(
                    text = "Allow Look After to silence interruptions during Anchored blocks.",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.8f),
                )
            }
        }
    }
}

private fun subtitle(
    state: LifeState,
    restoredFromDisk: Boolean,
    hydrationComplete: Boolean,
): String {
    val day = (state.currentDay ?: LocalDate.now())
        .format(DateTimeFormatter.ofPattern("EEEE, MMM d"))
    val pending = state.activeTasks.count { it.status.isActive }
    val persistence = when {
        !hydrationComplete -> "loading…"
        restoredFromDisk -> "restored"
        else -> "fresh"
    }
    return "$day · $pending open · $persistence"
}
