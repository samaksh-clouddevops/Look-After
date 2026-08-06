import Foundation

public enum GapSeverity: String, Codable, Sendable {
    case nudge
    case important
}

public struct LifeGap: Identifiable, Sendable, Equatable {
    public let id: String
    public var commitmentTitle: String
    public var message: String
    public var severity: GapSeverity
    public var suggestedAction: String
    public var daysSinceLastCompletion: Int

    public init(
        commitmentTitle: String,
        message: String,
        severity: GapSeverity,
        suggestedAction: String,
        daysSinceLastCompletion: Int
    ) {
        self.id = commitmentTitle.lowercased()
        self.commitmentTitle = commitmentTitle
        self.message = message
        self.severity = severity
        self.suggestedAction = suggestedAction
        self.daysSinceLastCompletion = daysSinceLastCompletion
    }
}

/// Compares life commitments against recent completion history.
public enum LifeGapDetector {

    public static func detect(
        model: LifeModel,
        allTasks: [LifeTask],
        habitsCompletedToday: Set<String> = [],
        now: Date = Date(),
        calendar: Calendar = .current,
        lookbackDays: Int = 7
    ) -> [LifeGap] {
        guard model.hasContent else { return [] }

        var gaps: [LifeGap] = []

        for commitment in model.commitments.sorted(by: { $0.priority < $1.priority }) {
            guard commitment.frequency.applies(on: now, calendar: calendar) else { continue }

            let matching = allTasks.filter { matches(commitment: commitment, task: $0, model: model) }

            if isSatisfiedToday(
                commitment: commitment,
                matching: matching,
                allTasks: allTasks,
                habitsCompletedToday: habitsCompletedToday,
                now: now,
                calendar: calendar
            ) {
                continue
            }

            let lastCompleted = latestCompletionDate(
                for: commitment,
                matching: matching,
                allTasks: allTasks,
                habitsCompletedToday: habitsCompletedToday,
                calendar: calendar
            )

            let daysSince: Int
            if let lastCompleted {
                daysSince = max(
                    0,
                    calendar.dateComponents(
                        [.day],
                        from: calendar.startOfDay(for: lastCompleted),
                        to: calendar.startOfDay(for: now)
                    ).day ?? 0
                )
            } else {
                daysSince = lookbackDays + 1
            }

            let threshold = commitment.isNonNegotiable ? 1 : 2
            guard daysSince >= threshold else { continue }

            let blockLabel = commitment.preferredBlockLabel ?? "today"
            let severity: GapSeverity = daysSince >= 4 || commitment.isNonNegotiable ? .important : .nudge

            gaps.append(
                LifeGap(
                    commitmentTitle: commitment.title,
                    message: gapMessage(for: commitment.title, daysSince: daysSince, hasKnownHistory: lastCompleted != nil),
                    severity: severity,
                    suggestedAction: gapAction(minutes: commitment.defaultMinutes, blockLabel: blockLabel),
                    daysSinceLastCompletion: daysSince
                )
            )
        }

        return gaps.sorted {
            if $0.severity != $1.severity {
                return $0.severity == .important
            }
            return $0.daysSinceLastCompletion > $1.daysSinceLastCompletion
        }
    }

    /// Backward-compatible entry point — prefer `allTasks` with full persisted history.
    public static func detect(
        model: LifeModel,
        completedTasks: [LifeTask],
        activeTasks: [LifeTask],
        now: Date = Date(),
        calendar: Calendar = .current,
        lookbackDays: Int = 7
    ) -> [LifeGap] {
        detect(
            model: model,
            allTasks: completedTasks + activeTasks,
            now: now,
            calendar: calendar,
            lookbackDays: lookbackDays
        )
    }

    // MARK: - Satisfaction

    private static func isSatisfiedToday(
        commitment: LifeCommitment,
        matching: [LifeTask],
        allTasks: [LifeTask],
        habitsCompletedToday: Set<String>,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        if matching.contains(where: { isCompleted(on: now, task: $0, calendar: calendar) }) {
            return true
        }

        if isExerciseLike(commitment), habitsCompletedToday.contains("workout") {
            return true
        }
        if isExerciseLike(commitment),
           allTasks.contains(where: { isCompleted(on: now, task: $0, calendar: calendar) && isExerciseTask($0) }) {
            return true
        }

        if commitment.lifeArea == .creativity,
           allTasks.contains(where: { isCompleted(on: now, task: $0, calendar: calendar) && isCreativeWorkTask($0) }) {
            return true
        }

        return false
    }

    private static func latestCompletionDate(
        for commitment: LifeCommitment,
        matching: [LifeTask],
        allTasks: [LifeTask],
        habitsCompletedToday: Set<String>,
        calendar: Calendar
    ) -> Date? {
        var candidates: [Date] = matching
            .filter { $0.status == .completed }
            .compactMap { completionDate(for: $0) }

        if isExerciseLike(commitment) {
            candidates.append(contentsOf: allTasks
                .filter { $0.status == .completed && isExerciseTask($0) }
                .compactMap { completionDate(for: $0) })
            if habitsCompletedToday.contains("workout") {
                candidates.append(calendar.startOfDay(for: Date()))
            }
        }

        if commitment.lifeArea == .creativity {
            candidates.append(contentsOf: allTasks
                .filter { $0.status == .completed && isCreativeWorkTask($0) }
                .compactMap { completionDate(for: $0) })
        }

        return candidates.max()
    }

    // MARK: - Matching

    static func matches(commitment: LifeCommitment, task: LifeTask, model: LifeModel) -> Bool {
        let commitmentTag = model.commitmentID(for: commitment.title)
        if task.tags.contains(commitmentTag) { return true }

        let taskTitle = normalized(task.title)
        let commitmentTitle = normalized(commitment.title)
        if taskTitle == commitmentTitle { return true }

        if task.tags.contains(LifeModel.commitmentTaskTag), taskTitle == commitmentTitle {
            return true
        }

        if titlesOverlap(taskTitle, commitmentTitle) {
            return true
        }

        let keywords = Self.commitmentKeywords(for: commitment.title)
        if keywords.contains(where: { taskTitle.contains($0) }) {
            return true
        }

        let taskKeywords = Self.commitmentKeywords(for: task.title)
        if taskKeywords.contains(where: { commitmentTitle.contains($0) || keywords.contains($0) }) {
            return true
        }

        if task.tags.contains(LifeModel.commitmentTaskTag) {
            if isExerciseLike(commitment) && isExerciseTask(task) { return true }
            if commitment.lifeArea == .creativity && isCreativeWorkTask(task) { return true }
        }

        return false
    }

    static func completionDate(for task: LifeTask) -> Date? {
        guard task.status == .completed else { return nil }
        if let completedAt = task.completedAt { return completedAt }
        if task.updatedAt.timeIntervalSince1970 > 0 { return task.updatedAt }
        if task.tags.contains(LifeModel.commitmentTaskTag), let scheduled = task.scheduledDate {
            return scheduled
        }
        return nil
    }

    private static func isCompleted(on day: Date, task: LifeTask, calendar: Calendar) -> Bool {
        guard task.status == .completed, let date = completionDate(for: task) else { return false }
        return calendar.isDate(date, inSameDayAs: day)
    }

    private static func isExerciseLike(_ commitment: LifeCommitment) -> Bool {
        let title = normalized(commitment.title)
        return title.contains("gym")
            || title.contains("workout")
            || title.contains("exercise")
            || title.contains("run")
            || title.contains("training")
    }

    private static func isExerciseTask(_ task: LifeTask) -> Bool {
        let title = normalized(task.title)
        if title.contains("gym") || title.contains("workout") || title.contains("exercise") || title.contains("run") {
            return true
        }
        return task.tags.contains(where: { $0.contains("gym") || $0.contains("workout") })
    }

    private static func isCreativeWorkTask(_ task: LifeTask) -> Bool {
        if task.lifeArea == .creativity { return true }
        let title = normalized(task.title)
        if title.contains("music") || title.contains("production") || title.contains("creative")
            || title.contains("writing") || title.contains("project") || title.contains("mix") {
            return true
        }
        if task.tags.contains(LifeModel.commitmentTaskTag),
           task.tags.contains(where: { $0.contains("creative") || $0.contains("music") || $0.contains("project") }) {
            return true
        }
        return false
    }

    private static func titlesOverlap(_ lhs: String, _ rhs: String) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        if lhs.contains(rhs) || rhs.contains(lhs) { return true }
        let lhsTokens = Set(lhs.split(separator: " ").map(String.init))
        let rhsTokens = Set(rhs.split(separator: " ").map(String.init))
        return !lhsTokens.intersection(rhsTokens).isEmpty
    }

    private static func commitmentKeywords(for title: String) -> [String] {
        let lower = normalized(title)
        var keywords = lower
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 3 }

        switch lower {
        case let value where value.contains("gym") || value.contains("workout"):
            keywords.append(contentsOf: ["gym", "workout", "exercise", "training", "run"])
        case let value where value.contains("music") || value.contains("creative") || value.contains("production"):
            keywords.append(contentsOf: ["music", "production", "creative", "mix", "record", "writing", "project"])
        case let value where value.contains("writing"):
            keywords.append(contentsOf: ["writing", "write", "journal"])
        case let value where value.contains("project"):
            keywords.append(contentsOf: ["project", "creative", "side"])
        default:
            break
        }

        return Array(Set(keywords))
    }

    private static func gapMessage(for title: String, daysSince: Int, hasKnownHistory: Bool) -> String {
        if !hasKnownHistory {
            return "\(title). Not logged recently"
        }
        if daysSince == 1 {
            return "\(title). Not since yesterday"
        }
        return "\(title). \(daysSince) days since you last did it"
    }

    private static func gapAction(minutes: Int, blockLabel: String) -> String {
        if blockLabel.lowercased() == "today" {
            return "Try \(minutes) min sometime today"
        }
        return "Try \(minutes) min in your \(blockLabel) block"
    }

    private static func normalized(_ title: String) -> String {
        title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
