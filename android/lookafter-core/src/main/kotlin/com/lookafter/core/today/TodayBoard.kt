package com.lookafter.core.today

import com.lookafter.core.brain.HeroTaskRanker
import com.lookafter.core.engine.LifeState
import com.lookafter.core.health.HealthSummary
import com.lookafter.core.models.ConstraintType
import com.lookafter.core.models.LifeTask
import com.lookafter.core.models.Medication
import com.lookafter.core.models.Priority
import com.lookafter.core.models.TaskStatus
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId

/** Filter chip on the Today surface. */
enum class TodayFilter {
    ALL,
    ANCHORED,
    FLEXIBLE,
    FLUID,
    DONE,
    HIGH_PRIORITY,
}

/** Board section buckets (iOS Timeline grouping parity). */
enum class TodaySectionKind {
    IN_PROGRESS,
    ANCHORED,
    FLEXIBLE,
    FLUID,
    COMPLETED,
}

data class TodaySection(
    val kind: TodaySectionKind,
    val title: String,
    val tasks: List<LifeTask>,
) {
    val count: Int get() = tasks.size
}

data class DayLoadSummary(
    val openCount: Int = 0,
    val doneCount: Int = 0,
    val totalMinutes: Int = 0,
    val doneMinutes: Int = 0,
    val anchoredCount: Int = 0,
    val completionRate: Double = 0.0,
    /** 0..1 rough capacity used (open+done minutes vs 8h). */
    val loadRatio: Double = 0.0,
    val loadLabel: String = "Light",
)

data class MedsStripItem(
    val id: String,
    val name: String,
    val timeLabel: String,
    val isTaken: Boolean,
    val isDue: Boolean,
)

/**
 * Pure projection of [LifeState] into the Today UI model.
 * No Android — unit-tested board layout.
 */
object TodayBoard {

    fun dayTasks(state: LifeState, day: LocalDate = state.currentDay ?: LocalDate.now()): List<LifeTask> {
        // Include tasks scheduled for day OR undated active (inbox fluid).
        return state.activeTasks.filter { task ->
            val d = task.scheduledDate
            d == null || d == day
        }
    }

    fun filter(tasks: List<LifeTask>, filter: TodayFilter): List<LifeTask> = when (filter) {
        TodayFilter.ALL -> tasks
        TodayFilter.ANCHORED -> tasks.filter {
            it.status.isActive && it.constraintType == ConstraintType.ANCHORED
        }
        TodayFilter.FLEXIBLE -> tasks.filter {
            it.status.isActive && it.constraintType == ConstraintType.FLEXIBLE
        }
        TodayFilter.FLUID -> tasks.filter {
            it.status.isActive && it.constraintType == ConstraintType.FLUID
        }
        TodayFilter.DONE -> tasks.filter { it.status == TaskStatus.COMPLETED }
        TodayFilter.HIGH_PRIORITY -> tasks.filter {
            it.status.isActive &&
                (it.priority == Priority.CRITICAL || it.priority == Priority.HIGH)
        }
    }

    fun sections(
        tasks: List<LifeTask>,
        filter: TodayFilter = TodayFilter.ALL,
    ): List<TodaySection> {
        val filtered = filter(tasks, filter)
        fun sortKey(t: LifeTask): Instant = t.scheduledStart ?: Instant.MAX

        val inProgress = filtered.filter { it.status == TaskStatus.IN_PROGRESS || it.status == TaskStatus.PAUSED }
            .sortedBy(::sortKey)
        val active = filtered.filter { it.status == TaskStatus.PENDING }
        val anchored = active.filter { it.constraintType == ConstraintType.ANCHORED }.sortedBy(::sortKey)
        val flexible = active.filter { it.constraintType == ConstraintType.FLEXIBLE }.sortedBy(::sortKey)
        val fluid = active.filter { it.constraintType == ConstraintType.FLUID }.sortedBy(::sortKey)
        val done = filtered.filter { it.status == TaskStatus.COMPLETED }
            .sortedByDescending { it.completedAt ?: Instant.EPOCH }

        // When filter is a single bucket, collapse to one section.
        return when (filter) {
            TodayFilter.ANCHORED -> listOfNotNull(
                section(TodaySectionKind.ANCHORED, "Anchored", anchored + inProgress.filter { it.constraintType == ConstraintType.ANCHORED }),
            )
            TodayFilter.FLEXIBLE -> listOfNotNull(
                section(TodaySectionKind.FLEXIBLE, "Flexible", flexible + inProgress.filter { it.constraintType == ConstraintType.FLEXIBLE }),
            )
            TodayFilter.FLUID -> listOfNotNull(
                section(TodaySectionKind.FLUID, "Fluid", fluid + inProgress.filter { it.constraintType == ConstraintType.FLUID }),
            )
            TodayFilter.DONE -> listOfNotNull(section(TodaySectionKind.COMPLETED, "Done", done))
            TodayFilter.HIGH_PRIORITY, TodayFilter.ALL -> buildList {
                section(TodaySectionKind.IN_PROGRESS, "In progress", inProgress)?.let(::add)
                section(TodaySectionKind.ANCHORED, "Anchored", anchored)?.let(::add)
                section(TodaySectionKind.FLEXIBLE, "Flexible", flexible)?.let(::add)
                section(TodaySectionKind.FLUID, "Fluid", fluid)?.let(::add)
                if (filter == TodayFilter.ALL) {
                    section(TodaySectionKind.COMPLETED, "Done", done)?.let(::add)
                }
            }
        }
    }

    fun loadSummary(tasks: List<LifeTask>): DayLoadSummary {
        val open = tasks.filter { it.status.isActive }
        val done = tasks.filter { it.status == TaskStatus.COMPLETED }
        val openMin = open.sumOf { it.durationMinutes.coerceAtLeast(0) }
        val doneMin = done.sumOf { it.durationMinutes.coerceAtLeast(0) }
        val total = openMin + doneMin
        val denom = (open.size + done.size).coerceAtLeast(1)
        val rate = done.size.toDouble() / denom.toDouble()
        val load = (total / (8.0 * 60.0)).coerceIn(0.0, 1.5)
        val label = when {
            load >= 1.0 -> "Heavy"
            load >= 0.65 -> "Full"
            load >= 0.35 -> "Steady"
            else -> "Light"
        }
        return DayLoadSummary(
            openCount = open.size,
            doneCount = done.size,
            totalMinutes = total,
            doneMinutes = doneMin,
            anchoredCount = open.count { it.constraintType == ConstraintType.ANCHORED },
            completionRate = rate,
            loadRatio = load.coerceIn(0.0, 1.0),
            loadLabel = label,
        )
    }

    fun hero(state: LifeState, now: Instant = Instant.now()): HeroTaskRanker.HeroSelection =
        HeroTaskRanker.select(state, now)

    fun medsStrip(
        meds: List<Medication>,
        now: LocalTime = LocalTime.now(),
        zone: ZoneId = ZoneId.systemDefault(),
    ): List<MedsStripItem> {
        // zone reserved for future local-date alignment
        return meds.sortedBy { it.scheduledTime }.map { m ->
            val due = !m.isTaken && !m.scheduledTime.isAfter(now)
            MedsStripItem(
                id = m.id,
                name = m.name,
                timeLabel = m.scheduledTime.toString().substring(0, 5),
                isTaken = m.isTaken,
                isDue = due,
            )
        }
    }

    fun availableTags(tasks: List<LifeTask>): List<String> =
        tasks.flatMap { it.tags }
            .filter { it.isNotBlank() && it != "capture" && it != "plan" && it != "manual" }
            .distinct()
            .sorted()

    fun filterByTag(tasks: List<LifeTask>, tag: String?): List<LifeTask> {
        if (tag.isNullOrBlank()) return tasks
        return tasks.filter { tag in it.tags }
    }

    private fun section(kind: TodaySectionKind, title: String, tasks: List<LifeTask>): TodaySection? =
        if (tasks.isEmpty()) null else TodaySection(kind, title, tasks)
}
