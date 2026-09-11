import Foundation
import LookAfterAI
import LookAfterCore

/// Generates short "For today" hero copy from tasks, timeline, and capacity signals.
/// Prefer ≤2 scannable lines (ADHD load); greeting already owns the name — never repeat it here.
enum BriefingDayHeroSummaryGenerator {

    /// Hard cap on hero bullets — greeting + CTA already fill the first viewport.
    static let maxHeroLines = 2
    /// Soft cap per line so bullets stay scannable on a phone.
    static let maxLineCharacters = 90

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
            if let lines = parseLines(raw), lines.count >= 1 {
                return polish(Array(lines.prefix(maxHeroLines)))
            }
        } catch {}
        return deterministic
    }

    private static func polish(_ lines: [String]) -> [String] {
        Array(
            lines
                .map { UserFacingCopy.humanizeBriefingLine($0) }
                .map { truncateLine($0) }
                .filter { !$0.isEmpty }
                .prefix(maxHeroLines)
        )
    }

    private static func truncateLine(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLineCharacters else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: maxLineCharacters - 1)
        var slice = String(trimmed[..<end])
        if let lastSpace = slice.lastIndex(of: " "), lastSpace > slice.startIndex {
            slice = String(slice[..<lastSpace])
        }
        return slice.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
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
        let pending = input.mission.tasks.filter { !$0.isCompleted }
        let done = input.mission.tasks.filter(\.isCompleted)

        // Prefer a single "what next" line when something is in progress.
        if let ongoing = input.tasks.first(where: { $0.status == .inProgress }) {
            lines.append(capacityPhrase(input))
            lines.append("Pick up \"\(formatTitleForList(ongoing.title))\".")
            return Array(lines.prefix(maxHeroLines))
        }

        let now = Date()
        if let currentEvent = ongoingTimelineEvent(in: input.lifeTimelineEvents, now: now) {
            lines.append(capacityPhrase(input))
            lines.append(Self.underwayLine(for: currentEvent.title))
            return Array(lines.prefix(maxHeroLines))
        }

        // Line 1 — how the day feels (no name; greeting owns that)
        if input.sleep.isAvailable, let hours = input.sleep.totalHours {
            let sleepPhrase = hours >= 7 ? "decent sleep" : "a short night"
            lines.append(String(format: "%.1fh %@ · %@", hours, sleepPhrase, capacityPhrase(input)))
        } else {
            let sleepBit = missingSleepPrefix(input)
            lines.append(sleepBit.isEmpty ? capacityPhrase(input) : "\(sleepBit)\(capacityPhrase(input))")
        }

        // Line 2 — next action or compact task count (not a full list dump)
        if let plan = input.dayBriefing, !plan.planItems.isEmpty,
           let first = plan.planItems.first(where: { !$0.isCompleted }) {
            if let label = first.timeLabel, !label.isEmpty,
               label.compare("Now", options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame {
                lines.append("Next: \(formatTitleForList(first.title)) at \(label).")
            } else {
                lines.append("Next: \(formatTitleForList(first.title)).")
            }
            return Array(lines.prefix(maxHeroLines))
        }

        if let title = input.calendar.nextEventTitle, let mins = input.calendar.minutesUntilStart {
            let when = mins <= 90 ? "in \(mins) min" : "later"
            lines.append("\(formatTitleForList(title)) \(when).")
            return Array(lines.prefix(maxHeroLines))
        }

        if pending.isEmpty, done.isEmpty, input.progress.remainingCount == 0 {
            lines.append("List is empty — add one thing that finishes the day.")
        } else if pending.isEmpty {
            lines.append("\(done.count) done. Open time if you want it.")
        } else {
            let starter = mainPendingTask(from: pending, lifeTasks: input.tasks) ?? pending[0]
            let top = formatTitleForList(starter.title)
            var taskLine = "\(pending.count) left"
            if input.progress.overdueCount > 0 {
                taskLine += ", \(input.progress.overdueCount) overdue"
            }
            if let minutes = input.dayBriefing?.plannedMinutesRemaining, minutes > 0 {
                taskLine += " · \(formatWorkMinutes(minutes))"
            }
            taskLine += ". Start with \(top)."
            lines.append(taskLine)
        }

        return Array(lines.prefix(maxHeroLines))
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

    /// Prefer morning / next-window tasks for the hero "Start with" cue.
    private static func mainPendingTask(
        from pending: [BriefingMissionTask],
        lifeTasks: [LifeTask],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> BriefingMissionTask? {
        guard !pending.isEmpty else { return nil }
        let byId = Dictionary(uniqueKeysWithValues: lifeTasks.map { ($0.id, $0) })
        let day = calendar.startOfDay(for: now)
        let hour = calendar.component(.hour, from: now)

        let ranked = pending.sorted { lhs, rhs in
            let left = byId[lhs.id].map { TaskListSorter.nextActionableTime(for: $0, on: day, calendar: calendar) } ?? .distantFuture
            let right = byId[rhs.id].map { TaskListSorter.nextActionableTime(for: $0, on: day, calendar: calendar) } ?? .distantFuture
            if left != right { return left < right }
            return lhs.priority > rhs.priority
        }

        let windowRelevant = ranked.filter { mission in
            guard let task = byId[mission.id] else { return false }
            switch TaskScheduleInterval.displaySchedule(for: task, on: day, calendar: calendar) {
            case .window(let start, _, _):
                let startHour = calendar.component(.hour, from: start)
                if hour < 12 {
                    return startHour < 14
                }
                return start <= now.addingTimeInterval(4 * 3600)
            case .unslottedFlexible:
                return hour < 12
            case .noSchedule:
                return false
            }
        }

        return windowRelevant.first ?? ranked.first
    }

    private static func formatTitleForList(_ title: String) -> String {
        let separators = [" — ", "—", " – ", "–"]
        for separator in separators {
            let parts = title.components(separatedBy: separator)
            if parts.count == 2 {
                let head = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let tail = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !head.isEmpty, !tail.isEmpty else { break }
                return "\(head) (\(tail))"
            }
        }
        return title
    }

    /// Avoid awkward "Take medication is underway" grammar.
    private static func underwayLine(for title: String) -> String {
        let cleaned = formatTitleForList(title)
        let lower = cleaned.lowercased()
        if lower.contains("medication") || lower.hasPrefix("take med") || lower == "meds" {
            return "Medication is underway. Stay with it."
        }
        if lower.hasPrefix("take ") {
            let rest = String(cleaned.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !rest.isEmpty {
                return "\(rest.prefix(1).uppercased())\(rest.dropFirst()) is underway. Stay with it."
            }
        }
        return "\"\(cleaned)\" is underway. Stay with it."
    }

    private static func formatWorkMinutes(_ minutes: Int) -> String {
        if minutes < 60 { return "\(max(1, minutes)) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 { return "\(hours)h" }
        return "\(hours)h \(remainder)m"
    }

    private static func missingSleepPrefix(_ input: Input) -> String {
        input.sleep.isAvailable ? "" : "No sleep data from last night. "
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
        Max \(maxHeroLines) lines. Each line under \(maxLineCharacters) characters.
        Do not greet or use the user's name — the UI greeting already did that.

        Capacity: \(input.executiveCapacity.band.displayLabel). \(input.executiveCapacity.band.tagline)
        Energy: \(input.energy.currentEnergyPercent)%
        Sleep hours: \(input.sleep.totalHours.map { String(format: "%.1f", $0) } ?? "unknown")
        Tasks left: \(input.progress.remainingCount)
        Done today: \(input.progress.completedCount)
        Overdue: \(overdue.count)
        Planned minutes left: \(input.dayBriefing?.plannedMinutesRemaining ?? 0)

        Still to do:
        \(pendingTasks.prefix(4).map { "- \($0.title)" }.joined(separator: "\n"))

        Done:
        \(completedTasks.prefix(3).map { "- \($0.title)" }.joined(separator: "\n"))

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
