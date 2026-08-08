package com.lookafter.app.ui.timeline

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.outlined.DoNotDisturbOn
import androidx.compose.material.icons.outlined.SelfImprovement
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.lookafter.app.execution.SystemFocusController
import com.lookafter.app.ui.components.CalmEmptyState
import com.lookafter.app.ui.components.ElevatedSurfaceCard
import com.lookafter.app.ui.components.SectionHeader
import com.lookafter.app.ui.theme.LookAfterColors
import com.lookafter.app.ui.theme.LookAfterDimens
import com.lookafter.core.engine.LifeState
import com.lookafter.core.engine.LookAfterIntent
import com.lookafter.core.models.LifeTask
import com.lookafter.core.today.DayLoadSummary
import com.lookafter.core.today.MedsStripItem
import com.lookafter.core.today.TodayBoard
import com.lookafter.core.today.TodayFilter
import com.lookafter.core.today.TodaySectionKind
import java.time.LocalDate
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import kotlin.math.roundToInt

/** Full Today surface — load, hero, meds, filters, sections, DND (iOS Timeline parity). */
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
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        policyGrantedState.value = SystemFocusController.isPolicyAccessGranted(context)
    }
    val policyGranted by policyGrantedState

    var filter by remember { mutableStateOf(TodayFilter.ALL) }
    var tag by remember { mutableStateOf<String?>(null) }

    val day = state.currentDay ?: LocalDate.now()
    val dayTasks = remember(state.activeTasks, day) { TodayBoard.dayTasks(state, day) }
    val tags = remember(dayTasks) { TodayBoard.availableTags(dayTasks) }
    val tagged = remember(dayTasks, tag) { TodayBoard.filterByTag(dayTasks, tag) }
    val sections = remember(tagged, filter) { TodayBoard.sections(tagged, filter) }
    val load = remember(dayTasks) { TodayBoard.loadSummary(dayTasks) }
    val meds = remember(state.medications) { TodayBoard.medsStrip(state.medications, LocalTime.now()) }
    val hero = remember(state.activeTasks) { TodayBoard.hero(state) }
    val displayHeroTitle = heroTitle ?: hero.task?.title
    val displayHeroReason = heroReason ?: hero.reason
    val dayLabel = day.format(DateTimeFormatter.ofPattern("EEEE, MMM d"))

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(
            horizontal = LookAfterDimens.screenHorizontal,
            vertical = LookAfterDimens.spacingMD,
        ),
        verticalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingSM),
    ) {
        item(key = "header") {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
                SectionHeader(
                    title = "Today",
                    subtitle = "$dayLabel\n" + subtitle(state, load, restoredFromDisk, hydrationComplete),
                    modifier = Modifier.weight(1f),
                )
                if (onCreateTask != null) {
                    IconButton(onClick = onCreateTask) {
                        Icon(Icons.Filled.Add, contentDescription = "New task", tint = LookAfterColors.AccentPrimary)
                    }
                }
            }
        }
        item(key = "load") { DayLoadCard(load) }
        if (!displayHeroTitle.isNullOrBlank()) {
            item(key = "hero") {
                HeroCard(
                    title = displayHeroTitle,
                    reason = displayHeroReason.orEmpty(),
                    onStartFocus = onStartFocus,
                    onOpen = hero.task?.let { t -> onOpenTask?.let { cb -> { cb(t) } } },
                )
            }
        }
        if (meds.isNotEmpty()) {
            item(key = "meds") {
                MedsStrip(meds) { id, taken ->
                    onIntent(LookAfterIntent.TakeMedication(id = id, taken = taken))
                }
            }
        }
        item(key = "filters") {
            FilterRow(filter, { filter = it }, tags, tag) { t -> tag = if (tag == t) null else t }
        }
        if (!policyGranted) item(key = "dnd") { DndCard() }

        if (sections.isEmpty()) {
            item(key = "empty") {
                CalmEmptyState(
                    title = if (filter == TodayFilter.ALL && tag == null) "Equilibrium achieved" else "Nothing in this view",
                    subtitle = if (filter == TodayFilter.ALL && tag == null) {
                        "Capture a thought, schedule deep work, or protect the quiet."
                    } else "Try another filter or clear the tag chip.",
                    icon = Icons.Outlined.SelfImprovement,
                    actionLabel = if (onCreateTask != null && filter == TodayFilter.ALL) "New task" else null,
                    onAction = onCreateTask,
                    modifier = Modifier.fillMaxWidth().padding(top = 32.dp),
                )
            }
        } else {
            sections.forEach { section ->
                item(key = "h-${section.kind}") {
                    SectionLabel(section.kind, section.title, section.count)
                }
                items(section.tasks, key = { it.id }) { task ->
                    TimelineTaskCard(
                        task = task,
                        onIntent = onIntent,
                        onOpen = onOpenTask,
                        showFocus = onStartFocus != null && task.status.isActive,
                        onFocus = onStartFocus,
                    )
                }
            }
        }
        item { Spacer(Modifier.height(LookAfterDimens.spacingXL)) }
    }
}

@Composable
private fun DayLoadCard(load: DayLoadSummary) {
    ElevatedSurfaceCard {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Column {
                Text("Day load", style = MaterialTheme.typography.labelMedium, color = LookAfterColors.AccentPrimary)
                Text(
                    "${load.loadLabel} · ${load.openCount} open · ${load.doneCount} done",
                    style = MaterialTheme.typography.titleLarge,
                    modifier = Modifier.padding(top = 2.dp),
                )
            }
            Text("${(load.completionRate * 100).roundToInt()}%", style = MaterialTheme.typography.headlineMedium, color = LookAfterColors.AccentPrimary)
        }
        LinearProgressIndicator(
            progress = { load.completionRate.toFloat().coerceIn(0f, 1f) },
            modifier = Modifier.fillMaxWidth().padding(top = LookAfterDimens.spacingSM).height(8.dp),
            color = LookAfterColors.AccentPrimary,
        )
        Text(
            "${load.doneMinutes}m done · ${load.totalMinutes}m planned · ${load.anchoredCount} anchored",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
        )
    }
}

@Composable
private fun HeroCard(title: String, reason: String, onStartFocus: (() -> Unit)?, onOpen: (() -> Unit)?) {
    ElevatedSurfaceCard {
        Text("Next up", style = MaterialTheme.typography.labelMedium, color = LookAfterColors.AccentPrimary)
        Text(
            title,
            style = MaterialTheme.typography.titleLarge,
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier
                .padding(top = LookAfterDimens.spacingXXS)
                .then(if (onOpen != null) Modifier.clickable(onClick = onOpen) else Modifier),
        )
        if (reason.isNotBlank()) {
            Text(
                reason,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
            )
        }
        if (onStartFocus != null) {
            Button(
                onClick = onStartFocus,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = LookAfterDimens.spacingSM),
                colors = ButtonDefaults.buttonColors(
                    containerColor = LookAfterColors.AccentPrimary,
                    contentColor = LookAfterColors.AccentOnPrimary,
                ),
            ) { Text("Begin focus") }
            if (onOpen != null) {
                Text(
                    "Tap title to edit",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
                )
            }
        }
    }
}

@Composable
private fun MedsStrip(meds: List<MedsStripItem>, onToggle: (String, Boolean) -> Unit) {
    ElevatedSurfaceCard {
        Text("Medications", style = MaterialTheme.typography.labelMedium, color = LookAfterColors.Health)
        Row(
            modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(top = LookAfterDimens.spacingSM),
            horizontalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingSM),
        ) {
            meds.forEach { m ->
                FilterChip(
                    selected = m.isTaken,
                    onClick = { onToggle(m.id, !m.isTaken) },
                    label = { Text("${m.name} ${m.timeLabel}${if (m.isDue && !m.isTaken) " · due" else ""}") },
                    colors = FilterChipDefaults.filterChipColors(
                        selectedContainerColor = LookAfterColors.AccentSoft,
                        selectedLabelColor = LookAfterColors.AccentPrimary,
                    ),
                )
            }
        }
    }
}

@Composable
private fun FilterRow(
    selected: TodayFilter,
    onSelect: (TodayFilter) -> Unit,
    tags: List<String>,
    selectedTag: String?,
    onTag: (String) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingXS)) {
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingXS)) {
            TodayFilter.entries.forEach { f ->
                FilterChip(
                    selected = selected == f,
                    onClick = { onSelect(f) },
                    label = { Text(filterLabel(f)) },
                    colors = FilterChipDefaults.filterChipColors(
                        selectedContainerColor = LookAfterColors.AccentSoft,
                        selectedLabelColor = LookAfterColors.AccentPrimary,
                    ),
                )
            }
        }
        if (tags.isNotEmpty()) {
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingXS)) {
                tags.forEach { t ->
                    FilterChip(
                        selected = selectedTag == t,
                        onClick = { onTag(t) },
                        label = { Text("#$t") },
                        colors = FilterChipDefaults.filterChipColors(
                            selectedContainerColor = LookAfterColors.AccentSoft,
                            selectedLabelColor = LookAfterColors.AccentPrimary,
                        ),
                    )
                }
            }
        }
    }
}

@Composable
private fun SectionLabel(kind: TodaySectionKind, title: String, count: Int) {
    val color = when (kind) {
        TodaySectionKind.IN_PROGRESS -> LookAfterColors.Focus
        TodaySectionKind.ANCHORED -> LookAfterColors.Anchored
        TodaySectionKind.FLEXIBLE -> LookAfterColors.Flexible
        TodaySectionKind.FLUID -> LookAfterColors.Fluid
        TodaySectionKind.COMPLETED -> LookAfterColors.Success
    }
    Text(
        "$title · $count",
        style = MaterialTheme.typography.labelMedium,
        color = color,
        modifier = Modifier.padding(top = LookAfterDimens.spacingXS),
    )
}

@Composable
private fun DndCard() {
    val context = LocalContext.current
    ElevatedSurfaceCard(modifier = Modifier.clickable {
        context.startActivity(SystemFocusController.notificationPolicySettingsIntent())
    }) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(LookAfterDimens.spacingSM)) {
            Icon(Icons.Outlined.DoNotDisturbOn, contentDescription = null, tint = LookAfterColors.AccentPrimary)
            Column(Modifier.weight(1f)) {
                Text("Focus quieter with DND", style = MaterialTheme.typography.titleMedium)
                Text("Allow Do Not Disturb access for focus sessions.", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

private fun filterLabel(f: TodayFilter): String = when (f) {
    TodayFilter.ALL -> "All"
    TodayFilter.ANCHORED -> "Anchored"
    TodayFilter.FLEXIBLE -> "Flexible"
    TodayFilter.FLUID -> "Fluid"
    TodayFilter.DONE -> "Done"
    TodayFilter.HIGH_PRIORITY -> "High"
}

private fun subtitle(
    state: LifeState,
    load: DayLoadSummary,
    restoredFromDisk: Boolean,
    hydrationComplete: Boolean,
): String {
    if (!hydrationComplete) return "Restoring life state…"
    val base = "${load.openCount} open · ${load.doneCount} done · ${state.parkedQueue.size} parked"
    return if (restoredFromDisk) "$base · restored" else base
}
