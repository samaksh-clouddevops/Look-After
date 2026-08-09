import Foundation

/// Surfaces micro-tasks that fit in the gap before the next fixed commitment.
public enum WaitingModeAnalyzer {
    public struct Result: Sendable, Equatable {
        public var availableMinutes: Int
        public var anchorTitle: String
        public var fittingTasks: [LifeTask]

        public init(availableMinutes: Int, anchorTitle: String, fittingTasks: [LifeTask]) {
            self.availableMinutes = availableMinutes
            self.anchorTitle = anchorTitle
            self.fittingTasks = fittingTasks
        }
    }

    public static func analyze(
        tasks: [LifeTask],
        now: Date = Date(),
        calendar: Calendar = .current,
        bufferMinutes: Int = 5
    ) -> Result? {
        guard let fit = PreWindowFitAnalyzer.analyze(tasks: tasks, now: now, calendar: calendar) else { return nil }
        let available = max(0, fit.availableMinutes - bufferMinutes)
        guard available >= 8, available <= 45 else { return nil }

        let day = calendar.startOfDay(for: now)
        let candidates = tasks.filter { task in
            guard task.status.isActive, task.isSchedulerMovable else { return false }
            let minutes = TaskScheduleInterval.displayDurationMinutes(for: task, on: day, calendar: calendar)
            return minutes <= available
        }

        let ranked = candidates.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return lhs.estimatedMinutes < rhs.estimatedMinutes
        }

        guard !ranked.isEmpty else { return nil }

        return Result(
            availableMinutes: available,
            anchorTitle: fit.anchor.title,
            fittingTasks: Array(ranked.prefix(2))
        )
    }

    public static func proactiveAction(from result: Result) -> ProactiveAction {
        let taskTitles = result.fittingTasks.map(\.title).joined(separator: "\" or \"")
        return ProactiveAction(
            kind: .waitingMode,
            severity: .medium,
            message: "You have ~\(result.availableMinutes)m before \"\(result.anchorTitle)\" — knock out \"\(taskTitles)\"?",
            options: result.fittingTasks.map { "Start \($0.title)" } + ["Keep plan"],
            surface: .banner,
            relatedTaskIDs: result.fittingTasks.map(\.id),
            expiresAt: Date().addingTimeInterval(TimeInterval(result.availableMinutes * 60))
        )
    }
}
