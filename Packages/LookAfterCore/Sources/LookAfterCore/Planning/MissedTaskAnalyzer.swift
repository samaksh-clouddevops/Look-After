import Foundation

/// Classifies tasks after a life-context shift (late wake, going out, etc.).
public enum MissedTaskAnalyzer {

    public struct AwayWindow: Sendable, Equatable {
        public var start: Date
        public var end: Date

        public init(start: Date, end: Date) {
            self.start = start
            self.end = end
        }

        public func contains(_ date: Date) -> Bool {
            date >= start && date < end
        }

        public func overlaps(start: Date, end: Date) -> Bool {
            start < self.end && self.start < end
        }
    }

    public struct Result: Sendable, Equatable {
        public var missed: [LifeTask]
        public var salvageable: [LifeTask]
        public var protected: [LifeTask]
        public var minutesLate: Int?

        public init(
            missed: [LifeTask] = [],
            salvageable: [LifeTask] = [],
            protected: [LifeTask] = [],
            minutesLate: Int? = nil
        ) {
            self.missed = missed
            self.salvageable = salvageable
            self.protected = protected
            self.minutesLate = minutesLate
        }
    }

    public struct Input: Sendable {
        public var tasks: [LifeTask]
        public var now: Date
        public var wakeTime: Date?
        public var expectedWakeHour: Int
        public var awayWindow: AwayWindow?
        public var calendar: Calendar

        public init(
            tasks: [LifeTask],
            now: Date = Date(),
            wakeTime: Date? = nil,
            expectedWakeHour: Int = 7,
            awayWindow: AwayWindow? = nil,
            calendar: Calendar = .current
        ) {
            self.tasks = tasks
            self.now = now
            self.wakeTime = wakeTime
            self.expectedWakeHour = expectedWakeHour
            self.awayWindow = awayWindow
            self.calendar = calendar
        }
    }

    public static func analyze(_ input: Input) -> Result {
        let day = input.calendar.startOfDay(for: input.now)
        let active = input.tasks.filter { $0.status.isActive && $0.scheduledTime != nil }
        let referenceNow = input.wakeTime ?? input.now

        var missed: [LifeTask] = []
        var salvageable: [LifeTask] = []
        var protected: [LifeTask] = []

        for task in active {
            guard input.calendar.isDate(task.scheduledDate ?? day, inSameDayAs: day) else { continue }

            if task.isFixedTimeEvent || task.isLifeCommitmentTask {
                if isMissed(task, on: day, before: referenceNow, calendar: input.calendar) {
                    missed.append(task)
                } else {
                    protected.append(task)
                }
                continue
            }

            if isMissed(task, on: day, before: referenceNow, calendar: input.calendar) {
                missed.append(task)
            } else if let away = input.awayWindow,
                      let window = TaskScheduleInterval.window(for: task, on: day, calendar: input.calendar),
                      away.overlaps(start: window.start, end: window.end) {
                salvageable.append(task)
            } else {
                salvageable.append(task)
            }
        }

        let minutesLate = computeMinutesLate(
            wakeTime: input.wakeTime ?? input.now,
            expectedWakeHour: input.expectedWakeHour,
            day: day,
            calendar: input.calendar
        )

        return Result(
            missed: missed,
            salvageable: salvageable,
            protected: protected,
            minutesLate: minutesLate
        )
    }

    private static func isMissed(
        _ task: LifeTask,
        on day: Date,
        before reference: Date,
        calendar: Calendar
    ) -> Bool {
        guard let window = TaskScheduleInterval.window(for: task, on: day, calendar: calendar) else {
            return false
        }
        return window.end <= reference
    }

    private static func computeMinutesLate(
        wakeTime: Date,
        expectedWakeHour: Int,
        day: Date,
        calendar: Calendar
    ) -> Int? {
        guard let expected = calendar.date(
            bySettingHour: min(max(expectedWakeHour, 0), 23),
            minute: 0,
            second: 0,
            of: day
        ) else { return nil }
        let delta = Int(wakeTime.timeIntervalSince(expected) / 60)
        return delta > 0 ? delta : nil
    }
}
