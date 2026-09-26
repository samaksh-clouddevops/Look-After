import Foundation

/// Prioritises fixed-time commitments and prevents the engine from treating them as movable.
public struct FixedTimeEventRule: FlowSchedulingRuleProtocol {
    public let identifier = "FixedTimeEventRule"

    public init() {}

    public func apply(to state: inout MutableSchedulingState, context: FlowSchedulingContext) {
        let now = context.input.currentTime
        let fixedNow = context.activeTasks.filter { $0.isActiveFixedTimeWindow(at: now, calendar: context.calendar) }

        guard !fixedNow.isEmpty else { return }

        let hero = fixedNow.min { lhs, rhs in
            let lStart = lhs.scheduledTime ?? .distantFuture
            let rStart = rhs.scheduledTime ?? .distantFuture
            if lStart != rStart { return lStart < rStart }
            return lhs.priority.rawValue > rhs.priority.rawValue
        }

        if let hero {
            state.heroTask = hero
            state.suggestedDurationMinutes = remainingMinutes(for: hero, at: now, calendar: context.calendar)
            state.actionType = hero.status == .inProgress ? .continue : .start
            state.reasoningLines.append("Fixed commitment — \(hero.title) is scheduled now.")
        }

        state.appliedRuleIDs.append(identifier)
    }

    private func remainingMinutes(for task: LifeTask, at now: Date, calendar: Calendar) -> Int {
        // A missing scheduledDate still carries a day in the clock. Do not remap it onto now.
        if let assigned = task.assignedDay(calendar: calendar),
           !calendar.isDate(assigned, inSameDayAs: now) {
            return FlowTaskSelector.effectiveMinutes(for: task)
        }
        guard let start = task.scheduledTime,
              let windowStart = calendar.combine(date: calendar.startOfDay(for: now), timeFrom: start) else {
            return FlowTaskSelector.effectiveMinutes(for: task)
        }
        let end: Date
        if let scheduledEnd = task.scheduledEndTime,
           let windowEnd = calendar.combine(date: calendar.startOfDay(for: now), timeFrom: scheduledEnd) {
            end = windowEnd > windowStart ? windowEnd : windowEnd.addingTimeInterval(24 * 3600)
        } else {
            end = windowStart.addingTimeInterval(TimeInterval(max(task.estimatedMinutes, 15) * 60))
        }
        let remaining = Int(end.timeIntervalSince(now) / 60)
        return max(5, min(remaining, FlowTaskSelector.effectiveMinutes(for: task)))
    }
}
