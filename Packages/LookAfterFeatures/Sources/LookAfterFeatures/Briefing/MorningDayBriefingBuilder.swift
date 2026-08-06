import Foundation
import LookAfterCore

enum MorningDayBriefingBuilder {

    struct BuildInput: Sendable {
        var postWake: PostWakeDetector.Result
        var healthSummary: HealthSummary?
        var sleep: BriefingSleepData
        var executiveCapacity: ExecutiveCapacityState
        var lifeSnapshot: LifeContextSnapshot?
        var lifeTimelineEvents: [LifeTimelineEvent]
        var tomorrowTimelineEvents: [LifeTimelineEvent]
        var tasks: [LifeTask]
        var completedToday: [LifeTask]
        var calendarData: BriefingCalendarData
        var focusWindowLabel: String?
        var now: Date
        var calendar: Calendar

        init(
            postWake: PostWakeDetector.Result,
            healthSummary: HealthSummary?,
            sleep: BriefingSleepData,
            executiveCapacity: ExecutiveCapacityState,
            lifeSnapshot: LifeContextSnapshot?,
            lifeTimelineEvents: [LifeTimelineEvent],
            tomorrowTimelineEvents: [LifeTimelineEvent] = [],
            tasks: [LifeTask],
            completedToday: [LifeTask],
            calendarData: BriefingCalendarData,
            focusWindowLabel: String?,
            now: Date = Date(),
            calendar: Calendar = .current
        ) {
            self.postWake = postWake
            self.healthSummary = healthSummary
            self.sleep = sleep
            self.executiveCapacity = executiveCapacity
            self.lifeSnapshot = lifeSnapshot
            self.lifeTimelineEvents = lifeTimelineEvents
            self.tomorrowTimelineEvents = tomorrowTimelineEvents
            self.tasks = tasks
            self.completedToday = completedToday
            self.calendarData = calendarData
            self.focusWindowLabel = focusWindowLabel
            self.now = now
            self.calendar = calendar
        }
    }

    static func build(_ input: BuildInput) -> MorningDayBriefing {
        let postWake = input.postWake
        let healthSummary = input.healthSummary
        let sleep = input.sleep
        let executiveCapacity = input.executiveCapacity
        let lifeSnapshot = input.lifeSnapshot
        let lifeTimelineEvents = input.lifeTimelineEvents
        let tomorrowTimelineEvents = input.tomorrowTimelineEvents
        let tasks = input.tasks
        let completedToday = input.completedToday
        let calendarData = input.calendarData
        let focusWindowLabel = input.focusWindowLabel
        let now = input.now
        let calendar = input.calendar
        let profile = UserLifeProfileStore.load()
        let sleepLine = buildSleepLine(postWake: postWake, health: healthSummary, sleep: sleep, calendar: calendar)
        let idealSleep = IdealSleepPlanner.recommend(
            IdealSleepPlanner.Input(
                now: now,
                targetSleepHours: IdealSleepPlanner.defaultTargetSleepHours(),
                sleepDebtHours: sleep.sleepDebtHours,
                todayTimelineEvents: lifeTimelineEvents,
                tomorrowTimelineEvents: tomorrowTimelineEvents,
                tasks: tasks,
                profile: profile,
                lifeModel: LifeModelStore.load(),
                calendar: calendar
            )
        )
        let timeLabels = buildTimeLabels(
            lifeSnapshot: lifeSnapshot,
            calendarData: calendarData,
            focusWindowLabel: focusWindowLabel,
            workEndHour: profile.workEndHour,
            now: now,
            calendar: calendar
        )

        let activeToday = tasks.filter { $0.status.isActive && isRelevantToday($0, now: now, calendar: calendar) }
        let overdue = tasks.filter(\.isOverdue)
        let plannedMinutes = activeToday.reduce(0) { partial, task in
            partial + max(task.estimatedMinutes, 0)
        }

        let planItems = buildPlanItems(from: lifeTimelineEvents, now: now, calendar: calendar)
        let pendingHighlights = buildPendingHighlights(
            overdue: overdue,
            activeToday: activeToday,
            completedToday: completedToday,
            lifeTimelineEvents: lifeTimelineEvents,
            now: now,
            calendar: calendar
        )

        let intro = buildIntroLine(
            postWake: postWake,
            freeTimeLabel: timeLabels.free,
            remainingCount: activeToday.count,
            plannedMinutes: plannedMinutes
        )

        return MorningDayBriefing(
            headline: "Your day at a glance",
            introLine: intro,
            sleepLine: sleepLine,
            idealSleepLine: idealSleep?.line,
            idealBedtime: idealSleep?.bedtime,
            capacityLabel: executiveCapacity.band.displayLabel,
            capacityTagline: executiveCapacity.band.tagline,
            freeTimeLabel: timeLabels.free,
            nextEventLabel: timeLabels.nextEvent,
            focusWindowLabel: timeLabels.focus,
            workEndLabel: timeLabels.workEnd,
            completedCount: completedToday.count,
            remainingCount: activeToday.count,
            overdueCount: overdue.count,
            plannedMinutesRemaining: plannedMinutes,
            planItems: planItems,
            pendingHighlights: pendingHighlights
        )
    }

    // MARK: - Private

    private struct TimeLabels {
        var free: String?
        var nextEvent: String?
        var focus: String?
        var workEnd: String?
    }

    private static func buildSleepLine(
        postWake: PostWakeDetector.Result,
        health: HealthSummary?,
        sleep: BriefingSleepData,
        calendar: Calendar
    ) -> String? {
        var parts: [String] = []

        if let hours = sleep.totalHours {
            parts.append(String(format: "%.1fh sleep", hours))
        }

        if let wake = postWake.wakeTime ?? health?.wakeTime {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            parts.append("up since \(formatter.string(from: wake))")
        } else if let minutes = postWake.minutesSinceWake, minutes > 0 {
            parts.append("about \(minutes) min ago")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func buildTimeLabels(
        lifeSnapshot: LifeContextSnapshot?,
        calendarData: BriefingCalendarData,
        focusWindowLabel: String?,
        workEndHour: Int,
        now: Date,
        calendar: Calendar
    ) -> TimeLabels {
        var free: String?
        if let minutes = lifeSnapshot?.availableTimeMinutes, minutes > 0 {
            free = formatMinutes(minutes) + " open"
        } else if let block = lifeSnapshot?.calendarAvailability.freeBlockMinutes, block > 0 {
            free = formatMinutes(block) + " before next event"
        }

        var nextEvent: String?
        if let title = calendarData.nextEventTitle ?? lifeSnapshot?.calendarAvailability.nextEventTitle {
            if let mins = calendarData.minutesUntilStart ?? lifeSnapshot?.calendarAvailability.minutesUntilNextEvent {
                nextEvent = "\(title) in \(formatMinutes(mins))"
            } else {
                nextEvent = title
            }
        }

        var workEnd: String?
        if let end = calendar.date(bySettingHour: min(max(workEndHour, 0), 23), minute: 0, second: 0, of: now) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            workEnd = "Day ends ~\(formatter.string(from: end))"
        }

        let focus = focusWindowLabel.flatMap { label in
            label == UserFacingCopy.noFocusWindowToday ? nil : label
        }

        return TimeLabels(free: free, nextEvent: nextEvent, focus: focus, workEnd: workEnd)
    }

    private static func buildIntroLine(
        postWake: PostWakeDetector.Result,
        freeTimeLabel: String?,
        remainingCount: Int,
        plannedMinutes: Int
    ) -> String {
        if postWake.isPostWake {
            var parts: [String] = ["Ease in — here is how today is shaped."]
            if let freeTimeLabel {
                parts.append("You have \(freeTimeLabel.lowercased()).")
            }
            if remainingCount > 0 {
                parts.append("\(remainingCount) task\(remainingCount == 1 ? "" : "s") on deck")
                if plannedMinutes > 0 {
                    parts.append("(~\(formatMinutes(plannedMinutes)) planned).")
                } else {
                    parts.append(".")
                }
            } else {
                parts.append("Nothing urgent is queued yet.")
            }
            return parts.joined(separator: " ")
        }

        var parts: [String] = []
        if remainingCount > 0 {
            parts.append("\(remainingCount) task\(remainingCount == 1 ? "" : "s") left")
            if plannedMinutes > 0 {
                parts.append("· ~\(formatMinutes(plannedMinutes)) planned")
            }
        } else {
            parts.append("No open tasks on the board")
        }
        if let freeTimeLabel {
            parts.append("· \(freeTimeLabel)")
        }
        return parts.joined(separator: " ")
    }

    private static func buildPlanItems(
        from events: [LifeTimelineEvent],
        now: Date,
        calendar: Calendar
    ) -> [MorningPlanItem] {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"

        return events
            .filter { calendar.isDate($0.date, inSameDayAs: now) }
            .sorted { $0.date < $1.date }
            .prefix(8)
            .map { event in
                let isOngoing = !event.isCompleted && event.date <= now
                let timeText: String?
                if event.isCompleted {
                    timeText = formatter.string(from: event.date)
                } else if isOngoing {
                    timeText = "Now"
                } else {
                    timeText = formatter.string(from: event.date)
                }
                return MorningPlanItem(
                    id: event.id,
                    timeLabel: timeText,
                    title: event.title,
                    subtitle: event.subtitle.isEmpty ? nil : event.subtitle,
                    isCompleted: event.isCompleted,
                    kind: kind(for: event.kind)
                )
            }
    }

    private static func buildPendingHighlights(
        overdue: [LifeTask],
        activeToday: [LifeTask],
        completedToday: [LifeTask],
        lifeTimelineEvents: [LifeTimelineEvent],
        now: Date,
        calendar: Calendar
    ) -> [String] {
        var lines: [String] = []

        if !overdue.isEmpty {
            let titles = overdue.prefix(2).map(\.title).joined(separator: ", ")
            lines.append(overdue.count == 1 ? "Overdue: \(titles)" : "\(overdue.count) overdue — \(titles)")
        }

        let meds = lifeTimelineEvents.filter {
            $0.kind == .medication && !$0.isCompleted && calendar.isDate($0.date, inSameDayAs: now)
        }
        if !meds.isEmpty {
            lines.append("\(meds.count) medication\(meds.count == 1 ? "" : "s") on today's plan")
        }

        let bills = lifeTimelineEvents.filter { $0.kind == .bill && !$0.isCompleted }
        if !bills.isEmpty {
            lines.append("\(bills.count) bill\(bills.count == 1 ? "" : "s") need attention")
        }

        if completedToday.isEmpty, activeToday.count >= 6 {
            lines.append("Full day — start with the first scheduled block")
        }

        return Array(lines.prefix(4))
    }

    private static func kind(for eventKind: LifeTimelineEventKind) -> MorningPlanItem.Kind {
        switch eventKind {
        case .meeting: return .calendar
        case .medication: return .medication
        case .bill, .finance: return .bill
        case .habit, .health, .exercise, .recovery, .personal, .creative: return .routine
        default: return .task
        }
    }

    private static func isRelevantToday(_ task: LifeTask, now: Date, calendar: Calendar) -> Bool {
        if task.isOverdue { return true }
        if let scheduled = task.scheduledDate ?? task.scheduledTime {
            return calendar.isDate(scheduled, inSameDayAs: now)
        }
        if task.scheduledTime != nil { return true }
        return true
    }

    private static func formatMinutes(_ minutes: Int) -> String {
        if minutes < 60 { return "\(max(1, minutes)) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 { return "\(hours)h" }
        return "\(hours)h \(remainder)m"
    }
}
