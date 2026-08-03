import Foundation

public enum RecommendationConfidenceLevel: String, Codable, Sendable, CaseIterable {
    case high
    case medium
    case low

    public init(score: Double) {
        switch score {
        case 0.9...: self = .high
        case 0.6..<0.9: self = .medium
        default: self = .low
        }
    }

    public var displayHint: String? {
        switch self {
        case .high: return nil
        case .medium: return "Tap Why? to see how this was chosen"
        case .low: return "I'm not fully sure yet — you can change this"
        }
    }
}

public enum InsightSourceKind: String, Codable, Sendable {
    case sleep
    case calendar
    case energy
    case task
    case resume
    case health
    case behavior
    case weather
}

public enum InsightSourceDestination: String, Codable, Sendable {
    case healthSleep
    case healthOverview
    case calendar
    case taskDetail
    case none
}

public struct InsightMetricRow: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var value: String
    public var comparison: String?

    public init(id: String = UUID().uuidString, label: String, value: String, comparison: String? = nil) {
        self.id = id
        self.label = label
        self.value = value
        self.comparison = comparison
    }
}

/// Expandable insight with traceable source data.
public struct RecommendationInsight: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var headline: String
    public var detail: String
    public var sourceKind: InsightSourceKind
    public var metrics: [InsightMetricRow]
    public var sourceLabel: String
    public var destination: InsightSourceDestination
    public var learnMoreURL: String?

    public init(
        id: String = UUID().uuidString,
        headline: String,
        detail: String,
        sourceKind: InsightSourceKind,
        metrics: [InsightMetricRow] = [],
        sourceLabel: String,
        destination: InsightSourceDestination = .none,
        learnMoreURL: String? = nil
    ) {
        self.id = id
        self.headline = headline
        self.detail = detail
        self.sourceKind = sourceKind
        self.metrics = metrics
        self.sourceLabel = sourceLabel
        self.destination = destination
        self.learnMoreURL = learnMoreURL
    }
}

public enum InsightBuilder {
    public static func sleepInsight(
        snapshot: LifeContextSnapshot,
        health: HealthSummary?,
        targetSleepHours: Double = 7.5
    ) -> RecommendationInsight? {
        switch snapshot.sleepQuality {
        case .good, .excellent:
            return positiveSleepInsight(snapshot: snapshot, health: health, targetSleepHours: targetSleepHours)
        case .poor, .fair:
            return recoverySleepInsight(snapshot: snapshot, health: health, targetSleepHours: targetSleepHours)
        case .unknown:
            return nil
        }
    }

    private static func positiveSleepInsight(
        snapshot: LifeContextSnapshot,
        health: HealthSummary?,
        targetSleepHours: Double
    ) -> RecommendationInsight? {
        guard snapshot.sleepQuality == .good || snapshot.sleepQuality == .excellent else { return nil }

        let totalMin = health?.totalSleepMinutes ?? 0
        guard totalMin > 0 else { return nil }

        let hours = Int(totalMin) / 60
        let mins = Int(totalMin) % 60
        let sleepValue = "\(hours)h \(String(format: "%02d", mins))m"
        let deepMin = health?.deepSleepMinutes ?? 0

        let headline: String
        let detail: String
        switch snapshot.sleepQuality {
        case .excellent:
            headline = "Excellent sleep — strong recovery."
            detail = "Peak focus window is open — schedule demanding work before meetings stack up."
        case .good:
            headline = "Well rested — good momentum today."
            detail = "Your sleep supports deeper focus blocks. Use peak hours for the hardest task."
        default:
            return nil
        }

        return RecommendationInsight(
            headline: headline,
            detail: detail,
            sourceKind: .sleep,
            metrics: [
                InsightMetricRow(label: "Sleep", value: sleepValue, comparison: "Above \(String(format: "%.0f", targetSleepHours))h target"),
                InsightMetricRow(label: "Deep Sleep", value: deepMin > 0 ? "\(Int(deepMin)) min" : "—", comparison: nil),
                InsightMetricRow(label: "Recovery", value: snapshot.sleepQuality == .excellent ? "High" : "Good", comparison: nil)
            ],
            sourceLabel: "Imported from Apple Health",
            destination: .healthSleep
        )
    }

    private static func recoverySleepInsight(
        snapshot: LifeContextSnapshot,
        health: HealthSummary?,
        targetSleepHours: Double
    ) -> RecommendationInsight? {
        guard snapshot.sleepQuality == .poor || snapshot.sleepQuality == .fair else { return nil }

        let totalMin = health?.totalSleepMinutes ?? 0
        let deepMin = health?.deepSleepMinutes ?? 0
        let hours = Int(totalMin) / 60
        let mins = Int(totalMin) % 60
        let sleepValue = totalMin > 0 ? "\(hours)h \(String(format: "%02d", mins))m" : "Unavailable"
        let avgHours = Int(targetSleepHours)
        let avgMins = Int((targetSleepHours - Double(avgHours)) * 60)
        let avgValue = "\(avgHours)h \(String(format: "%02d", avgMins))m"

        let recovery: String = {
            switch snapshot.sleepQuality {
            case .poor: return "Low"
            case .fair: return "Moderate"
            default: return "Good"
            }
        }()

        return RecommendationInsight(
            headline: "Last night was rough.",
            detail: "Keep the first thing small — momentum matters more than size.",
            sourceKind: .sleep,
            metrics: [
                InsightMetricRow(label: "Sleep", value: sleepValue, comparison: nil),
                InsightMetricRow(label: "Average", value: avgValue, comparison: "Your target"),
                InsightMetricRow(label: "Deep Sleep", value: deepMin > 0 ? "\(Int(deepMin)) min" : "—", comparison: nil),
                InsightMetricRow(label: "Recovery", value: recovery, comparison: nil)
            ],
            sourceLabel: "Imported from Apple Health",
            destination: .healthSleep
        )
    }

    public static func calendarInsight(snapshot: LifeContextSnapshot) -> RecommendationInsight? {
        guard let event = snapshot.calendarAvailability.nextEventTitle,
              let mins = snapshot.calendarAvailability.minutesUntilNextEvent, mins > 0 else { return nil }
        return RecommendationInsight(
            headline: "\(event) in \(mins) minutes",
            detail: "Finishing before this keeps the rest of your day calmer.",
            sourceKind: .calendar,
            metrics: [
                InsightMetricRow(label: "Next event", value: event, comparison: nil),
                InsightMetricRow(label: "Starts in", value: "\(mins) min", comparison: nil),
                InsightMetricRow(label: "Free now", value: "\(snapshot.availableTimeMinutes) min", comparison: nil)
            ],
            sourceLabel: "From your Calendar",
            destination: .calendar
        )
    }
}
