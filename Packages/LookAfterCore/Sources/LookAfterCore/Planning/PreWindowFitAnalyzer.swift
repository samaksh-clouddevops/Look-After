import Foundation

/// Computes whether flexible tasks fit before the next fixed commitment (e.g. work in 20 min).
public enum PreWindowFitAnalyzer {

    public struct Anchor: Sendable, Equatable {
        public var taskID: String
        public var title: String
        public var start: Date
        public var minutesUntilStart: Int

        public init(taskID: String, title: String, start: Date, minutesUntilStart: Int) {
            self.taskID = taskID
            self.title = title
            self.start = start
            self.minutesUntilStart = minutesUntilStart
        }
    }

    public struct ShrinkSuggestion: Sendable, Equatable {
        public var taskID: String
        public var title: String
        public var currentMinutes: Int
        public var suggestedMinutes: Int

        public init(taskID: String, title: String, currentMinutes: Int, suggestedMinutes: Int) {
            self.taskID = taskID
            self.title = title
            self.currentMinutes = currentMinutes
            self.suggestedMinutes = suggestedMinutes
        }
    }

    public struct Result: Sendable, Equatable {
        public var anchor: Anchor
        public var availableMinutes: Int
        public var requiredMinutes: Int
        public var fittingTaskIDs: [String]
        public var shrinkSuggestions: [ShrinkSuggestion]
        public var skipTaskIDs: [String]

        public var isOvercommitted: Bool { requiredMinutes > availableMinutes }

        public init(
            anchor: Anchor,
            availableMinutes: Int,
            requiredMinutes: Int,
            fittingTaskIDs: [String] = [],
            shrinkSuggestions: [ShrinkSuggestion] = [],
            skipTaskIDs: [String] = []
        ) {
            self.anchor = anchor
            self.availableMinutes = availableMinutes
            self.requiredMinutes = requiredMinutes
            self.fittingTaskIDs = fittingTaskIDs
            self.shrinkSuggestions = shrinkSuggestions
            self.skipTaskIDs = skipTaskIDs
        }

        public var summaryLine: String {
            let name = anchor.title
            let until = anchor.minutesUntilStart
            if !isOvercommitted {
                return "\(name) in \(until)m — your flex tasks fit."
            }
            let over = requiredMinutes - availableMinutes
            var parts = ["\(name) in \(until)m — \(over)m short."]
            if !skipTaskIDs.isEmpty {
                parts.append("Skip \(skipTaskIDs.count).")
            }
            if !shrinkSuggestions.isEmpty {
                parts.append("Shrink \(shrinkSuggestions.count).")
            }
            return parts.joined(separator: " ")
        }
    }

    public static func analyze(
        tasks: [LifeTask],
        now: Date = Date(),
        horizonMinutes: Int = 120,
        bufferMinutes: Int = 5,
        calendar: Calendar = .current
    ) -> Result? {
        let day = calendar.startOfDay(for: now)
        guard let anchor = nextFixedAnchor(
            tasks: tasks,
            now: now,
            horizonMinutes: horizonMinutes,
            day: day,
            calendar: calendar
        ) else { return nil }

        let available = max(0, Int(anchor.start.timeIntervalSince(now) / 60) - bufferMinutes)
        let flexCandidates = flexibleTasksBeforeAnchor(
            tasks: tasks,
            anchorStart: anchor.start,
            anchorID: anchor.taskID,
            now: now,
            day: day,
            calendar: calendar
        )
        guard !flexCandidates.isEmpty else { return nil }

        let required = flexCandidates.reduce(0) { partial, task in
            partial + TaskScheduleInterval.displayDurationMinutes(for: task, on: day, calendar: calendar)
        }
        guard required > available else {
            return Result(
                anchor: anchor,
                availableMinutes: available,
                requiredMinutes: required,
                fittingTaskIDs: flexCandidates.map(\.id)
            )
        }

        var fitting: [String] = []
        var shrink: [ShrinkSuggestion] = []
        var skip: [String] = []
        var budget = available

        let sorted = flexCandidates.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return lhs.id < rhs.id
        }

        for task in sorted {
            let current = TaskScheduleInterval.displayDurationMinutes(for: task, on: day, calendar: calendar)
            let floor = TaskDurationPolicy.minimumMinutes
            if current <= budget {
                fitting.append(task.id)
                budget -= current
                continue
            }
            if budget >= floor, current > floor {
                shrink.append(ShrinkSuggestion(
                    taskID: task.id,
                    title: task.title,
                    currentMinutes: current,
                    suggestedMinutes: max(floor, budget)
                ))
                budget = 0
            } else {
                skip.append(task.id)
            }
        }

        return Result(
            anchor: anchor,
            availableMinutes: available,
            requiredMinutes: required,
            fittingTaskIDs: fitting,
            shrinkSuggestions: shrink,
            skipTaskIDs: skip
        )
    }

    private static func nextFixedAnchor(
        tasks: [LifeTask],
        now: Date,
        horizonMinutes: Int,
        day: Date,
        calendar: Calendar
    ) -> Anchor? {
        let horizonEnd = now.addingTimeInterval(TimeInterval(horizonMinutes * 60))
        var best: (task: LifeTask, start: Date)?

        for task in tasks where task.status.isActive {
            guard task.isFixedTimeEvent || task.isLifeCommitmentTask else { continue }
            guard let start = TaskScheduleInterval.resolvedStart(for: task, on: day, calendar: calendar) else {
                continue
            }
            guard start > now, start <= horizonEnd else { continue }
            if let current = best, start >= current.start { continue }
            best = (task, start)
        }

        guard let best else { return nil }
        let minutesUntil = max(1, Int(best.start.timeIntervalSince(now) / 60))
        return Anchor(
            taskID: best.task.id,
            title: best.task.title,
            start: best.start,
            minutesUntilStart: minutesUntil
        )
    }

    private static func flexibleTasksBeforeAnchor(
        tasks: [LifeTask],
        anchorStart: Date,
        anchorID: String,
        now: Date,
        day: Date,
        calendar: Calendar
    ) -> [LifeTask] {
        tasks.filter { task in
            guard task.status.isActive, task.id != anchorID else { return false }
            guard task.isSchedulerMovable else { return false }
            guard let start = TaskScheduleInterval.resolvedStart(for: task, on: day, calendar: calendar) else {
                return task.scheduledDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false
            }
            return start >= now && start < anchorStart
        }
    }
}
