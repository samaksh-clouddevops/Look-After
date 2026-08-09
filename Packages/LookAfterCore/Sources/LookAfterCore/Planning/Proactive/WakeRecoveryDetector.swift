import Foundation

/// Short sleep + dense calendar → bad-day template offer before app open.
public enum WakeRecoveryDetector {
    public struct Result: Sendable, Equatable {
        public var sleepHours: Double
        public var meetingCount: Int
        public var message: String

        public init(sleepHours: Double, meetingCount: Int, message: String) {
            self.sleepHours = sleepHours
            self.meetingCount = meetingCount
            self.message = message
        }
    }

    public static func evaluate(
        sleepHours: Double?,
        timelineEvents: [LifeTimelineEvent],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Result? {
        guard let sleepHours, sleepHours < 6 else { return nil }
        let meetings = timelineEvents.filter { event in
            calendar.isDateInToday(event.date) && (event.kind == .meeting || event.isFixed)
        }.count
        guard meetings >= 3 else { return nil }
        return Result(
            sleepHours: sleepHours,
            meetingCount: meetings,
            message: "Short night (\(String(format: "%.1f", sleepHours))h) and \(meetings) fixed blocks — want a gentler plan?"
        )
    }

    public static func proactiveAction(from result: Result, now: Date = Date()) -> ProactiveAction {
        ProactiveAction(
            kind: .badDay,
            severity: .high,
            message: result.message,
            options: ["Apply recovery", "Apply minimum", "Keep plan"],
            surface: .notification,
            expiresAt: now.addingTimeInterval(90 * 60),
            metadata: ["wakeRecovery": "true", "meetings": "\(result.meetingCount)"]
        )
    }
}
