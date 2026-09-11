import Foundation

/// Deterministic ideal bedtime recommendation from schedule + sleep targets.
public enum IdealSleepPlanner {

    public struct Recommendation: Sendable, Equatable {
        public var bedtime: Date
        public var sleepHours: Double
        public var wakeAnchorLabel: String
        public var line: String

        public init(bedtime: Date, sleepHours: Double, wakeAnchorLabel: String, line: String) {
            self.bedtime = bedtime
            self.sleepHours = sleepHours
            self.wakeAnchorLabel = wakeAnchorLabel
            self.line = line
        }
    }

    public struct Input: Sendable {
        public var now: Date
        public var targetSleepHours: Double
        public var sleepDebtHours: Double
        public var todayTimelineEvents: [LifeTimelineEvent]
        public var tomorrowTimelineEvents: [LifeTimelineEvent]
        public var tasks: [LifeTask]
        public var profile: UserLifeProfile
        public var lifeModel: LifeModel?
        public var calendar: Calendar
        /// Earliest hour (24h) to show ideal bedtime advice.
        public var showFromHour: Int

        public init(
            now: Date = Date(),
            targetSleepHours: Double = 8.0,
            sleepDebtHours: Double = 0,
            todayTimelineEvents: [LifeTimelineEvent] = [],
            tomorrowTimelineEvents: [LifeTimelineEvent] = [],
            tasks: [LifeTask] = [],
            profile: UserLifeProfile = UserLifeProfile(),
            lifeModel: LifeModel? = nil,
            calendar: Calendar = .current,
            showFromHour: Int = 17
        ) {
            self.now = now
            self.targetSleepHours = targetSleepHours
            self.sleepDebtHours = sleepDebtHours
            self.todayTimelineEvents = todayTimelineEvents
            self.tomorrowTimelineEvents = tomorrowTimelineEvents
            self.tasks = tasks
            self.profile = profile
            self.lifeModel = lifeModel
            self.calendar = calendar
            self.showFromHour = showFromHour
        }
    }

    private static let morningBufferMinutes = 45
    private static let maxDebtRecoveryHours = 1.5
    private static let eveningConflictBufferMinutes = 30

    public static func recommend(_ input: Input) -> Recommendation? {
        let hour = input.calendar.component(.hour, from: input.now)
        guard hour >= input.showFromHour else { return nil }

        guard let anchor = resolveTomorrowWakeAnchor(input) else { return nil }

        let sleepNeed = max(5.0, min(10.0, input.targetSleepHours + min(input.sleepDebtHours, maxDebtRecoveryHours)))
        let wakeTime = input.calendar.date(byAdding: .minute, value: -morningBufferMinutes, to: anchor.date) ?? anchor.date

        guard var bedtime = input.calendar.date(byAdding: .minute, value: -Int(sleepNeed * 60), to: wakeTime) else {
            return nil
        }

        // If bedtime falls before "now", it means sleep should have started — still show tonight on same calendar day.
        let todayStart = input.calendar.startOfDay(for: input.now)
        if bedtime < input.now {
            if let tonight = input.calendar.date(bySettingHour: 23, minute: 0, second: 0, of: todayStart) {
                bedtime = min(bedtime, tonight)
            }
        }

        var line = "Ideal tonight: \(formatTime(bedtime, calendar: input.calendar)) · \(formatSleepHours(sleepNeed)) for \(anchor.label)"

        if let conflict = eveningConflictNote(input: input, idealBedtime: bedtime) {
            line += " · \(conflict)"
        } else if input.sleepDebtHours >= 1 {
            line += " · catching up on sleep debt"
        }

        return Recommendation(
            bedtime: bedtime,
            sleepHours: sleepNeed,
            wakeAnchorLabel: anchor.label,
            line: line
        )
    }

    // MARK: - Anchor resolution

    private struct WakeAnchor {
        var date: Date
        var label: String
    }

    private static func resolveTomorrowWakeAnchor(_ input: Input) -> WakeAnchor? {
        guard let tomorrow = input.calendar.date(byAdding: .day, value: 1, to: input.calendar.startOfDay(for: input.now)) else {
            return nil
        }

        var candidates: [WakeAnchor] = []

        for event in input.tomorrowTimelineEvents where event.isFixed || isMorningKind(event.kind) {
            guard input.calendar.isDate(event.date, inSameDayAs: tomorrow) else { continue }
            let label = anchorLabel(for: event, calendar: input.calendar)
            candidates.append(WakeAnchor(date: event.date, label: label))
        }

        for task in input.tasks where task.status.isActive {
            guard let scheduledDate = task.scheduledDate,
                  input.calendar.isDate(scheduledDate, inSameDayAs: tomorrow),
                  let time = task.scheduledTime else { continue }
            let label = shortTaskAnchorLabel(task, time: time, calendar: input.calendar)
            let combined = input.calendar.combine(date: tomorrow, timeFrom: time) ?? time
            candidates.append(WakeAnchor(date: combined, label: label))
        }

        if let earliest = candidates.min(by: { $0.date < $1.date }) {
            return earliest
        }

        return fallbackWakeAnchor(input: input, tomorrow: tomorrow)
    }

    private static func fallbackWakeAnchor(input: Input, tomorrow: Date) -> WakeAnchor? {
        let weekday = input.calendar.component(.weekday, from: tomorrow)
        let isWeekend = weekday == 1 || weekday == 7

        if let model = input.lifeModel, model.hasContent {
            if !isWeekend, let office = model.timeBlocks.first(where: {
                let lower = $0.label.lowercased()
                return lower.contains("office") || lower.contains("work")
            }) {
                if let date = date(on: tomorrow, hour: office.startHour, minute: office.startMinute, calendar: input.calendar) {
                    return WakeAnchor(date: date, label: "\(formatTime(date, calendar: input.calendar)) office")
                }
            }
            if let gym = model.timeBlocks.first(where: { $0.label.lowercased().contains("gym") }) {
                if let date = date(on: tomorrow, hour: gym.startHour, minute: gym.startMinute, calendar: input.calendar) {
                    return WakeAnchor(date: date, label: "\(formatTime(date, calendar: input.calendar)) gym")
                }
            }
        }

        if !isWeekend {
            if let date = date(
                on: tomorrow,
                hour: input.profile.workStartHour,
                minute: input.profile.workStartMinute,
                calendar: input.calendar
            ) {
                return WakeAnchor(date: date, label: "\(formatTime(date, calendar: input.calendar)) office")
            }
        }

        if let date = date(on: tomorrow, hour: 9, minute: 0, calendar: input.calendar) {
            return WakeAnchor(date: date, label: "9:00 AM")
        }

        return nil
    }

    private static func eveningConflictNote(input: Input, idealBedtime: Date) -> String? {
        let todayStart = input.calendar.startOfDay(for: input.now)
        let windDownThreshold = input.calendar.date(
            byAdding: .minute,
            value: -eveningConflictBufferMinutes,
            to: idealBedtime
        ) ?? idealBedtime

        var latestEnd: Date?

        for event in input.todayTimelineEvents where event.isFixed {
            guard input.calendar.isDate(event.date, inSameDayAs: todayStart) else { continue }
            let end = event.date.addingTimeInterval(TimeInterval((event.estimatedMinutes ?? 45) * 60))
            if end > windDownThreshold {
                latestEnd = max(latestEnd ?? end, end)
            }
        }

        for task in input.tasks where task.status.isActive {
            guard let scheduledDate = task.scheduledDate,
                  input.calendar.isDate(scheduledDate, inSameDayAs: todayStart),
                  let start = task.scheduledTime else { continue }
            let duration = max(task.estimatedMinutes, 30)
            let combinedStart = input.calendar.combine(date: todayStart, timeFrom: start) ?? start
            let end = combinedStart.addingTimeInterval(TimeInterval(duration * 60))
            if end > windDownThreshold {
                latestEnd = max(latestEnd ?? end, end)
            }
        }

        guard let latestEnd else { return nil }
        return "tight — until \(formatTime(latestEnd, calendar: input.calendar))"
    }

    // MARK: - Helpers

    private static func isMorningKind(_ kind: LifeTimelineEventKind) -> Bool {
        switch kind {
        case .meeting, .exercise, .health, .creative, .work, .habit:
            return true
        default:
            return false
        }
    }

    private static func anchorLabel(for event: LifeTimelineEvent, calendar: Calendar) -> String {
        let time = formatTime(event.date, calendar: calendar)
        switch event.kind {
        case .exercise, .health:
            return "\(time) \(event.title.lowercased())"
        case .creative:
            return "\(time) \(event.title)"
        case .meeting:
            return "\(time) meeting"
        case .work:
            return "\(time) office"
        default:
            return "\(time) \(event.title)"
        }
    }

    private static func shortTaskAnchorLabel(_ task: LifeTask, time: Date, calendar: Calendar) -> String {
        let timeLabel = formatTime(time, calendar: calendar)
        return "\(timeLabel) \(task.title)"
    }

    private static func date(on day: Date, hour: Int, minute: Int, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: min(max(hour, 0), 23), minute: min(max(minute, 0), 59), second: 0, of: day)
    }

    private static func formatTime(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private static func formatSleepHours(_ hours: Double) -> String {
        if abs(hours - hours.rounded()) < 0.05 {
            return String(format: "%.0fh", hours)
        }
        return String(format: "%.1fh", hours)
    }

    /// Reads target sleep from UserDefaults when available.
    public static func defaultTargetSleepHours() -> Double {
        if let stored = UserDefaults.standard.object(forKey: "targetSleepHours") as? Double, stored > 0 {
            return stored
        }
        return 8.0
    }
}
