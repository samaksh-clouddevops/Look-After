import Foundation
import LookAfterAI
import LookAfterCore
import os

/// Generates the 3-line "For today" hero copy from tasks, timeline, and capacity signals.
enum BriefingDayHeroSummaryGenerator {

    struct Input: Sendable {
        var userName: String
        var dayBriefing: MorningDayBriefing?
        var mission: BriefingMissionData
        var progress: BriefingProgressData
        var executiveCapacity: ExecutiveCapacityState
        var energy: BriefingEnergyData
        var calendar: BriefingCalendarData
        var sleep: BriefingSleepData
        var tasks: [LifeTask]
        var completedToday: [LifeTask]
        var lifeTimelineEvents: [LifeTimelineEvent]
    }

    private static let logger = Logger(subsystem: "com.lookafter.app", category: "BriefingDayHero")

    static func generate(_ input: Input) async -> [String] {
        let deterministic = polish(buildDeterministic(input))
        guard shouldCallAI(input) else { return deterministic }

        let hasKey = GLMService.shared.hasConfiguredAPIKey
        guard hasKey else { return deterministic }

        let prompt = buildPrompt(input)
        do {
            let raw = try await GLMService.shared.complete(
                prompt: prompt,
                systemPrompt: LookAfterPrompts.briefingDayHeroSummarySystem,
                tier: .economy
            )
            if let lines = parseLines(raw), lines.count >= 2 {
                return polish(Array(lines.prefix(3)))
            }
        } catch {
            logger.debug("Day hero AI summary fell back to deterministic: \(error.localizedDescription, privacy: .public)")
        }
        return deterministic
    }

    private static func polish(_ lines: [String]) -> [String] {
        lines
            .map { UserFacingCopy.humanizeBriefingLine($0) }
            .filter { !$0.isEmpty }
    }

    private static func shouldCallAI(_ input: Input) -> Bool {
        !input.tasks.isEmpty
            || !input.completedToday.isEmpty
            || !input.lifeTimelineEvents.isEmpty
            || input.progress.remainingCount > 0
            || (input.dayBriefing?.planItems.isEmpty == false)
    }

    static func buildDeterministic(_ input: Input) -> [String] {
        var lines: [String] = []
        let name = input.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let pending = input.mission.tasks.filter { !$0.isCompleted }
        let done = input.mission.tasks.filter(\.isCompleted)

        // Line 1 — how the day feels
        if input.sleep.isAvailable, let hours = input.sleep.totalHours {
            let sleepPhrase = hours >= 7 ? "decent sleep" : "a short night"
            if name.isEmpty {
                lines.append(String(format: "You got %@ (%.1f hours). %@", sleepPhrase, hours, capacityPhrase(input)))
            } else {
                lines.append(String(format: "Hey %@. You got %@ (%.1f hours). %@", name, sleepPhrase, hours, capacityPhrase(input)))
            }
        } else if name.isEmpty {
            lines.append("Here's today. \(missingSleepPrefix(input))\(capacityPhrase(input))")
        } else {
            lines.append("Hey \(name). \(missingSleepPrefix(input))\(capacityPhrase(input))")
        }

        // Line 2 — task plan
        if pending.isEmpty, done.isEmpty, input.progress.remainingCount == 0 {
            lines.append("Your list is empty. Add one thing that would make today feel finished.")
        } else if pending.isEmpty {
            lines.append("You're through the scheduled stuff (\(done.count) done). Open time if you want it.")
        } else {
            let top = pending.prefix(3).map(\.title).joined(separator: ", ")
            var taskLine = "You've got \(pending.count) thing\(pending.count == 1 ? "" : "s") today"
            if input.progress.overdueCount > 0 {
                taskLine += ", and \(input.progress.overdueCount) \(input.progress.overdueCount == 1 ? "is" : "are") overdue"
            }
            if let minutes = input.dayBriefing?.plannedMinutesRemaining, minutes > 0 {
                taskLine += ". About \(formatWorkMinutes(minutes)) of work lined up"
            }
            taskLine += ". The main ones: \(top)."
            lines.append(taskLine)
        }

        // Line 3 — ongoing work, then next plan
        if let ongoing = input.tasks.first(where: { $0.status == .inProgress }) {
            lines.append("You're in the middle of \"\(ongoing.title)\" — pick up where you left off.")
            return Array(lines.prefix(3))
        }

        let now = Date()
        if let currentEvent = ongoingTimelineEvent(in: input.lifeTimelineEvents, now: now) {
            lines.append("\(currentEvent.title) is underway right now. Stay with it if you can.")
            return Array(lines.prefix(3))
        }

        if let plan = input.dayBriefing, !plan.planItems.isEmpty {
            let upcoming = plan.planItems.filter { !$0.isCompleted }.prefix(2)
            if let first = upcoming.first {
                let when = first.timeLabel.map { "\($0), " } ?? ""
                lines.append("Next on the plan is \(when)\(first.title). Start there if it helps.")
                return Array(lines.prefix(3))
            }
        }

        if let title = input.calendar.nextEventTitle, let mins = input.calendar.minutesUntilStart {
            let when = mins <= 90 ? "in \(mins) minutes" : "later"
            lines.append("\(title) is \(when). Maybe do one small task before that.")
        } else if let focus = input.dayBriefing?.focusWindowLabel, focus != UserFacingCopy.noFocusWindowToday {
            lines.append("Your best focus time looks like \(focus). Save the hard stuff for then.")
        } else if let highlight = input.dayBriefing?.pendingHighlights.first {
            lines.append(highlight.hasSuffix(".") ? highlight : highlight + ".")
        } else if let first = pending.first {
            lines.append("If you're not sure where to start, try \"\(first.title)\" first.")
        } else {
            lines.append("Scroll down when you want the full picture on tasks and health.")
        }

        return Array(lines.prefix(3))
    }

    private static func ongoingTimelineEvent(in events: [LifeTimelineEvent], now: Date) -> LifeTimelineEvent? {
        events
            .filter { !$0.isCompleted && $0.id.hasPrefix("task-") }
            .sorted { $0.date < $1.date }
            .last { event in
                guard event.date <= now else { return false }
                let durationMinutes = max(event.estimatedMinutes ?? 30, 1)
                let blockEnd = event.date.addingTimeInterval(TimeInterval(durationMinutes * 60))
                return now <= blockEnd.addingTimeInterval(30 * 60)
            }
    }

    private static func formatWorkMinutes(_ minutes: Int) -> String {
        if minutes < 60 { return "\(max(1, minutes)) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 { return "\(hours)h" }
        return "\(hours)h \(remainder)m"
    }

    private static func missingSleepPrefix(_ input: Input) -> String {
        input.sleep.isAvailable ? "" : "No sleep data from last night — "
    }

    private static func capacityPhrase(_ input: Input) -> String {
        switch input.executiveCapacity.band {
        case .peakFocus:
            return "You're feeling sharp today."
        case .goodCapacity:
            return "You're in a good spot for real work."
        case .moderateCapacity:
            return "Pace looks normal. Nothing wild."
        case .lowCapacity:
            return "Take it easy. Lighter tasks will land better."
        case .recoveryMode:
            return "Recovery day. Protect your energy."
        }
    }

    private static func buildPrompt(_ input: Input) -> String {
        let name = input.userName.isEmpty ? "User" : input.userName
        let pendingTasks = input.mission.tasks.filter { !$0.isCompleted }
        let completedTasks = input.mission.tasks.filter(\.isCompleted)
        let overdue = input.tasks.filter(\.isOverdue)

        var planLines: [String] = []
        if let briefing = input.dayBriefing {
            for item in briefing.planItems.prefix(8) {
                let time = item.timeLabel ?? "unscheduled"
                let status = item.isCompleted ? "done" : "pending"
                planLines.append("\(time), \(item.title) (\(status))")
            }
        }

        let timelineLines = input.lifeTimelineEvents
            .sorted { $0.date < $1.date }
            .prefix(8)
            .map { "\($0.scheduleRangeLabel), \($0.title)" }

        return """
        Write like you're texting \(name). Short, warm, human. No dashes or semicolons.

        Capacity: \(input.executiveCapacity.band.displayLabel). \(input.executiveCapacity.band.tagline)
        Energy: \(input.energy.currentEnergyPercent)%
        Sleep hours: \(input.sleep.totalHours.map { String(format: "%.1f", $0) } ?? "unknown")
        Tasks left: \(input.progress.remainingCount)
        Done today: \(input.progress.completedCount)
        Overdue: \(overdue.count)
        Planned minutes left: \(input.dayBriefing?.plannedMinutesRemaining ?? 0)

        Still to do:
        \(pendingTasks.map { "- \($0.title)" }.joined(separator: "\n"))

        Done:
        \(completedTasks.map { "- \($0.title)" }.joined(separator: "\n"))

        Today's plan:
        \(planLines.isEmpty ? "None" : planLines.joined(separator: "\n"))

        Calendar next: \(input.calendar.nextEventTitle ?? "none")
        """
    }

    private static func parseLines(_ raw: String) -> [String]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"),
           let data = String(trimmed[start...end]).data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let lines = object["lines"] as? [String] {
            let cleaned = lines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return cleaned.isEmpty ? nil : cleaned
        }

        let byNewline = trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("{") }
        return byNewline.count >= 2 ? byNewline : nil
    }
}
