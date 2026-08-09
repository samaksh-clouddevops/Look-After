import Foundation
import LookAfterCore

public enum RecoveryDayTemplate: String, Sendable, CaseIterable, Codable {
    case minimumViable
    case recovery
    case gentlePush

    public var label: String {
        switch self {
        case .minimumViable: return "Minimum viable"
        case .recovery: return "Recovery day"
        case .gentlePush: return "Gentle push"
        }
    }

    public var summary: String {
        switch self {
        case .minimumViable: return "Top 3 priorities only — everything else waits."
        case .recovery: return "Light day with rest blocks — defer non-essentials."
        case .gentlePush: return "One deep-work slot protected — defer the rest."
        }
    }
}

public struct BadDaySignal: Sendable, Equatable {
    public var score: Int
    public var reasons: [String]
    public var recommendedTemplate: RecoveryDayTemplate

    public init(score: Int, reasons: [String], recommendedTemplate: RecoveryDayTemplate) {
        self.score = score
        self.reasons = reasons
        self.recommendedTemplate = recommendedTemplate
    }
}

/// Detects rough days from capacity, sleep, deferrals, and cycle signals.
public enum BadDayDetector {
    public struct Input: Sendable {
        public var capacityBand: ExecutiveCapacityBand?
        public var sleepHours: Double?
        public var deferralCountToday: Int
        public var activeTaskCount: Int
        public var cyclePhaseLabel: String?

        public init(
            capacityBand: ExecutiveCapacityBand? = nil,
            sleepHours: Double? = nil,
            deferralCountToday: Int = 0,
            activeTaskCount: Int = 0,
            cyclePhaseLabel: String? = nil
        ) {
            self.capacityBand = capacityBand
            self.sleepHours = sleepHours
            self.deferralCountToday = deferralCountToday
            self.activeTaskCount = activeTaskCount
            self.cyclePhaseLabel = cyclePhaseLabel
        }
    }

    public static func evaluate(_ input: Input) -> BadDaySignal? {
        var score = 0
        var reasons: [String] = []

        if input.capacityBand == .recoveryMode {
            score += 3
            reasons.append("Low executive capacity")
        }
        if let sleep = input.sleepHours, sleep < 5.5 {
            score += 2
            reasons.append("Short sleep")
        }
        if input.deferralCountToday >= 3 {
            score += 2
            reasons.append("Multiple deferrals today")
        }
        if input.activeTaskCount >= 8 {
            score += 1
            reasons.append("Heavy task load")
        }
        if let phase = input.cyclePhaseLabel?.lowercased(), phase.contains("menstrual") {
            score += 1
            reasons.append("Cycle phase")
        }

        guard score >= 3 else { return nil }
        let template: RecoveryDayTemplate
        if score >= 5 || input.capacityBand == .recoveryMode {
            template = .recovery
        } else if score >= 4 {
            template = .minimumViable
        } else {
            template = .gentlePush
        }
        return BadDaySignal(score: score, reasons: reasons, recommendedTemplate: template)
    }

    public static func proactiveAction(from signal: BadDaySignal) -> ProactiveAction {
        ProactiveAction(
            id: "bad-day-\(signal.recommendedTemplate.rawValue)",
            kind: .badDay,
            severity: signal.score >= 5 ? .high : .medium,
            message: "Rough day signals: \(signal.reasons.joined(separator: ", ")). Apply \(signal.recommendedTemplate.label.lowercased()) template?",
            options: ["Apply \(signal.recommendedTemplate.label)", "Emergency mode", "Keep plan"],
            surface: .banner,
            metadata: ["template": signal.recommendedTemplate.rawValue]
        )
    }
}
