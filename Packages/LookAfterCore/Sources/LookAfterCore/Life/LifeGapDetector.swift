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
        completedTasks: [LifeTask],
        activeTasks: [LifeTask],
        now: Date = Date(),
        calendar: Calendar = .current,
        lookbackDays: Int = 7
    ) -> [LifeGap] {
        guard model.hasContent else { return [] }

        var gaps: [LifeGap] = []
        let allTasks = completedTasks + activeTasks
        let commitmentTasks = allTasks.filter { $0.tags.contains(LifeModel.commitmentTaskTag) }

        for commitment in model.commitments.sorted(by: { $0.priority < $1.priority }) {
            guard commitment.frequency.applies(on: now, calendar: calendar) else { continue }

            let matching = commitmentTasks.filter {
                normalized($0.title) == normalized(commitment.title)
                    || $0.tags.contains(model.commitmentID(for: commitment.title))
            }

            let lastCompleted = matching
                .compactMap(\.completedAt)
                .max()

            let daysSince: Int
            if let lastCompleted {
                daysSince = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: lastCompleted), to: calendar.startOfDay(for: now)).day ?? 0)
            } else {
                daysSince = lookbackDays + 1
            }

            let completedToday = matching.contains {
                $0.status == .completed && calendar.isDateInToday($0.completedAt ?? .distantPast)
            }
            let scheduledToday = matching.contains {
                guard let scheduled = $0.scheduledDate else { return false }
                return calendar.isDate(scheduled, inSameDayAs: now) && $0.status.isActive
            }

            if completedToday || (daysSince == 0 && scheduledToday) { continue }

            let threshold = commitment.isNonNegotiable ? 1 : 2
            guard daysSince >= threshold else { continue }

            let blockLabel = commitment.preferredBlockLabel ?? "today"
            let severity: GapSeverity = daysSince >= 4 || commitment.isNonNegotiable ? .important : .nudge
            let dayWord = daysSince == 1 ? "1 day" : "\(daysSince) days"

            gaps.append(
                LifeGap(
                    commitmentTitle: commitment.title,
                    message: "No \(commitment.title.lowercased()) in \(dayWord)",
                    severity: severity,
                    suggestedAction: "Slot \(commitment.defaultMinutes) min in \(blockLabel)",
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

    private static func normalized(_ title: String) -> String {
        title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
