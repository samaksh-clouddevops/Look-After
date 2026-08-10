package com.lookafter.core.behavior

import com.lookafter.core.serialization.InstantSerializer
import com.lookafter.core.serialization.LocalDateSerializer
import java.time.Instant
import java.time.LocalDate
import java.util.UUID
import kotlinx.serialization.Serializable

@Serializable
enum class HabitCadence {
    DAILY,
    WEEKDAYS,
    WEEKLY,
    ;

    val label: String
        get() = when (this) {
            DAILY -> "Daily"
            WEEKDAYS -> "Weekdays"
            WEEKLY -> "Weekly"
        }
}

@Serializable
data class Habit(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val subtitle: String = "",
    val cadence: HabitCadence = HabitCadence.DAILY,
    val archived: Boolean = false,
    /** YYYY-MM-DD strings for stable serialization without custom set codec issues. */
    val completedDays: List<String> = emptyList(),
    val currentStreak: Int = 0,
    val bestStreak: Int = 0,
    @Serializable(with = InstantSerializer::class)
    val createdAt: Instant = Instant.EPOCH,
) {
    fun isDoneOn(day: LocalDate): Boolean = day.toString() in completedDays

    fun completedLocalDates(): List<LocalDate> =
        completedDays.mapNotNull { runCatching { LocalDate.parse(it) }.getOrNull() }.sorted()
}

@Serializable
data class BehaviorState(
    val habits: List<Habit> = emptyList(),
) {
    val active: List<Habit> get() = habits.filterNot { it.archived }

    fun dueToday(today: LocalDate = LocalDate.now()): List<Habit> =
        active.filter { HabitScheduler.isScheduled(it, today) && !it.isDoneOn(today) }

    fun doneToday(today: LocalDate = LocalDate.now()): List<Habit> =
        active.filter { it.isDoneOn(today) }

    companion object {
        val EMPTY = BehaviorState()
    }
}

sealed class BehaviorIntent {
    data class AddHabit(val habit: Habit) : BehaviorIntent()
    data class UpdateHabit(val habit: Habit) : BehaviorIntent()
    data class DeleteHabit(val id: String) : BehaviorIntent()
    data class ArchiveHabit(val id: String, val archived: Boolean = true) : BehaviorIntent()
    data class ToggleCheckIn(
        val id: String,
        val day: LocalDate = LocalDate.now(),
        val now: Instant = Instant.now(),
    ) : BehaviorIntent()
    data class ReplaceState(val state: BehaviorState) : BehaviorIntent()
}

object HabitScheduler {
    fun isScheduled(habit: Habit, day: LocalDate): Boolean = when (habit.cadence) {
        HabitCadence.DAILY -> true
        HabitCadence.WEEKDAYS -> day.dayOfWeek.value in 1..5
        HabitCadence.WEEKLY -> true // any day counts toward weekly; streak uses consecutive scheduled days
    }
}

/**
 * Habit check-ins + streak math (Phase E5).
 * Streaks count consecutive *scheduled* days ending at [today] (or yesterday if not yet done today).
 */
object BehaviorEngine {

    fun reduce(current: BehaviorState, intent: BehaviorIntent): BehaviorState = when (intent) {
        is BehaviorIntent.AddHabit -> {
            val h = normalize(intent.habit)
            current.copy(habits = listOf(h) + current.habits)
        }
        is BehaviorIntent.UpdateHabit -> {
            val h = normalize(intent.habit)
            current.copy(habits = current.habits.map { if (it.id == h.id) h else it })
        }
        is BehaviorIntent.DeleteHabit ->
            current.copy(habits = current.habits.filterNot { it.id == intent.id })
        is BehaviorIntent.ArchiveHabit ->
            current.copy(
                habits = current.habits.map {
                    if (it.id == intent.id) it.copy(archived = intent.archived) else it
                },
            )
        is BehaviorIntent.ToggleCheckIn -> current.copy(
            habits = current.habits.map { h ->
                if (h.id != intent.id) h
                else toggleDay(h, intent.day)
            },
        )
        is BehaviorIntent.ReplaceState -> intent.state
    }

    fun toggleDay(habit: Habit, day: LocalDate): Habit {
        val key = day.toString()
        val days = habit.completedDays.toMutableList()
        if (key in days) days.remove(key) else days.add(key)
        val updated = habit.copy(completedDays = days.distinct().sorted())
        return recomputeStreaks(updated, asOf = day)
    }

    fun recomputeStreaks(habit: Habit, asOf: LocalDate = LocalDate.now()): Habit {
        val done = habit.completedDays.toSet()
        var streak = 0
        var cursor = asOf
        // If today is scheduled and not done, start streak from yesterday.
        if (HabitScheduler.isScheduled(habit, cursor) && habit.title.isNotEmpty() && cursor.toString() !in done) {
            cursor = cursor.minusDays(1)
        }
        // Walk back across scheduled days only.
        var guard = 0
        while (guard < 800) {
            if (!HabitScheduler.isScheduled(habit, cursor)) {
                cursor = cursor.minusDays(1)
                guard++
                continue
            }
            if (cursor.toString() in done) {
                streak++
                cursor = cursor.minusDays(1)
                guard++
            } else {
                break
            }
        }
        val best = maxOf(habit.bestStreak, streak)
        return habit.copy(currentStreak = streak, bestStreak = best)
    }

    fun completionRate(habit: Habit, windowDays: Int = 7, end: LocalDate = LocalDate.now()): Double {
        val start = end.minusDays((windowDays - 1).toLong())
        var scheduled = 0
        var hits = 0
        var d = start
        while (!d.isAfter(end)) {
            if (HabitScheduler.isScheduled(habit, d)) {
                scheduled++
                if (habit.isDoneOn(d)) hits++
            }
            d = d.plusDays(1)
        }
        if (scheduled == 0) return 0.0
        return hits.toDouble() / scheduled.toDouble()
    }

    private fun normalize(h: Habit): Habit {
        val now = Instant.now()
        val base = h.copy(
            title = h.title.trim().ifBlank { "Habit" },
            subtitle = h.subtitle.trim(),
            completedDays = h.completedDays.distinct().sorted(),
            createdAt = if (h.createdAt.epochSecond <= 0) now else h.createdAt,
        )
        return recomputeStreaks(base)
    }
}
