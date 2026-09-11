import Foundation

/// Escalating transition reminders before fixed anchors (time blindness shield).
public enum TransitionShieldBuilder {
    public struct Transition: Sendable, Equatable {
        public var eventID: String
        public var title: String
        public var start: Date
        public var minutesUntil: Int
        public var tier: Tier

        public enum Tier: Int, Sendable, CaseIterable {
            case thirty = 30
            case fifteen = 15
            case eight = 8
            case three = 3
        }

        public init(eventID: String, title: String, start: Date, minutesUntil: Int, tier: Tier) {
            self.eventID = eventID
            self.title = title
            self.start = start
            self.minutesUntil = minutesUntil
            self.tier = tier
        }
    }

    public static func transitions(
        timelineEvents: [LifeTimelineEvent],
        tasks: [LifeTask],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Transition] {
        var anchors: [(id: String, title: String, start: Date)] = []

        for event in timelineEvents where event.isFixed || event.kind == .meeting {
            guard event.date > now, calendar.isDateInToday(event.date) else { continue }
            anchors.append((event.id, event.title, event.date))
        }

        for task in tasks where task.isFixedTimeEvent || task.isLifeCommitmentTask {
            guard let start = TaskScheduleInterval.resolvedStart(for: task, on: calendar.startOfDay(for: now), calendar: calendar),
                  start > now else { continue }
            anchors.append((task.id, task.title, start))
        }

        anchors.sort { $0.start < $1.start }
        guard let next = anchors.first else { return [] }

        var results: [Transition] = []
        for tier in Transition.Tier.allCases.sorted(by: { $0.rawValue > $1.rawValue }) {
            let fireDate = next.start.addingTimeInterval(-TimeInterval(tier.rawValue * 60))
            guard fireDate > now else { continue }
            let minutesUntil = max(1, Int(next.start.timeIntervalSince(now) / 60))
            results.append(
                Transition(
                    eventID: next.id,
                    title: next.title,
                    start: next.start,
                    minutesUntil: min(minutesUntil, tier.rawValue),
                    tier: tier
                )
            )
        }
        return results
    }

    public static func proactiveActions(from transitions: [Transition], now: Date = Date()) -> [ProactiveAction] {
        transitions.map { transition in
            let prep: String
            switch transition.tier {
            case .three: prep = "Go now — close tabs and grab water."
            case .eight: prep = "Wrap up."
            case .fifteen: prep = "Heads up — start winding down."
            case .thirty: prep = "Anchor coming — glance at the plan."
            }
            let fireDate = transition.start.addingTimeInterval(-TimeInterval(transition.tier.rawValue * 60))
            return ProactiveAction(
                id: "transition-\(transition.eventID)-\(transition.tier.rawValue)",
                kind: .transitionShield,
                severity: transition.tier.rawValue <= 8 ? .high : .medium,
                message: "\"\(transition.title)\" in \(transition.minutesUntil)m — \(prep)",
                // V3: "I'm ready" is the single filled primary; Open plan / Snooze stay secondary.
                options: ["I'm ready", "Open plan", "Snooze 5m"],
                surface: .notification,
                relatedTaskIDs: [transition.eventID],
                expiresAt: transition.start,
                metadata: [
                    "tier": "\(transition.tier.rawValue)",
                    "eventStart": ISO8601DateFormatter().string(from: transition.start),
                    "fireDate": ISO8601DateFormatter().string(from: fireDate)
                ]
            )
        }
    }
}
