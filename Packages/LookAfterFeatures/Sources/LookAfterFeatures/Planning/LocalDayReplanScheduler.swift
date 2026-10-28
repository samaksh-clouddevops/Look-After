import Foundation
import LookAfterCore

/// Bounded local planning shared by offline replans and their preview variants.
/// Uses real durations, priorities and occupied intervals, including an away window.
enum LocalDayReplanScheduler {
    static func changes(context: DayReplanContext, tasks: [LifeTask]) -> [DayReplanScheduleChange] {
        let calendar = Calendar.current
        let now = context.planningContext.now
        let day = calendar.startOfDay(for: now)
        let pool = context.planningContext.tasks
        let candidates = tasks.filter {
            $0.status.isActive && $0.isSchedulerMovable && !$0.isRecurrenceTemplateTask
                && !$0.isLifeCommitmentTask && !MultiDayTaskTags.isRoot($0)
                && $0.isActionableToday(allTasks: pool, calendar: calendar, referenceDate: now)
        }.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            if $0.deadline != $1.deadline { return ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
            return $0.id < $1.id
        }
        let ids = Set(candidates.map(\.id))
        let hours = PlanningSchedulePolicy.WorkHours.from(profile: context.planningContext.lifeProfile)
        var blocked = SchedulingWindows.from(profile: context.planningContext.lifeProfile)
            .protectedIntervals(on: day, calendar: calendar)
        if let away = context.awayWindow {
            blocked.append(TaskScheduleInterval(taskID: "replan-away", start: away.start, end: away.end))
        }
        // Semantic hour bounds must still fit inside the user's workday.
        if let start = calendar.date(bySettingHour: hours.startHour, minute: hours.startMinute, second: 0, of: day),
           let end = hours.endDate(on: day, calendar: calendar),
           let nextDay = calendar.date(byAdding: .day, value: 1, to: day) {
            blocked.append(TaskScheduleInterval(taskID: "before-work", start: day, end: start))
            blocked.append(TaskScheduleInterval(taskID: "after-work", start: end, end: nextDay))
        }
        let allocations = DaySlotAllocator.allocate(
            requests: candidates.map { .makingSense(of: $0, on: day, calendar: calendar) },
            existingTasks: pool.filter { !ids.contains($0.id) },
            workHours: hours, referenceDay: day, now: now, calendar: calendar,
            extraBlocked: blocked
        )
        let starts = Dictionary.uniquingFirstValue(allocations.map { ($0.id, $0.scheduledTime) })
        return candidates.map { task in
            guard let start = starts[task.id] else {
                return DayReplanScheduleChange(taskID: task.id, deferToTomorrow: true,
                                               reason: "No room left today — moved to tomorrow")
            }
            return DayReplanScheduleChange(
                taskID: task.id, startHour: calendar.component(.hour, from: start),
                startMinute: calendar.component(.minute, from: start), reason: "Fits around commitments and priorities"
            )
        }
    }
}
