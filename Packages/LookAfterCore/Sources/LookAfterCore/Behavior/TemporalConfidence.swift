import Foundation

// MARK: - Time-of-day buckets

/// Coarse circadian bucket used by the Behavioral Vault.
public enum BehavioralTimeOfDay: String, Codable, Sendable, CaseIterable, Equatable {
    case morning
    case afternoon
    case evening

    /// Hour ranges (local clock): morning 5–11, afternoon 12–16, evening 17–4.
    public static func from(hour: Int) -> BehavioralTimeOfDay {
        switch hour {
        case 5..<12: return .morning
        case 12..<17: return .afternoon
        default: return .evening
        }
    }

    public static func from(date: Date, calendar: Calendar = .current) -> BehavioralTimeOfDay {
        from(hour: calendar.component(.hour, from: date))
    }
}

// MARK: - Temporal confidence

/// Confidence that `learnedConstraint` is correct, broken out by time of day (0…1).
public struct TemporalConfidence: Codable, Sendable, Equatable {
    public var morning: Double
    public var afternoon: Double
    public var evening: Double

    public static let neutral = TemporalConfidence(morning: 0.5, afternoon: 0.5, evening: 0.5)
    public static let high = TemporalConfidence(morning: 0.85, afternoon: 0.85, evening: 0.85)
    /// Seeded calendar baselines — one user override rewrites instantly (≤ 0.2).
    public static let seededLow = TemporalConfidence(morning: 0.2, afternoon: 0.2, evening: 0.2)

    public init(morning: Double, afternoon: Double, evening: Double) {
        self.morning = Self.clamp(morning)
        self.afternoon = Self.clamp(afternoon)
        self.evening = Self.clamp(evening)
    }

    public subscript(_ bucket: BehavioralTimeOfDay) -> Double {
        get {
            switch bucket {
            case .morning: return morning
            case .afternoon: return afternoon
            case .evening: return evening
            }
        }
        set {
            switch bucket {
            case .morning: morning = Self.clamp(newValue)
            case .afternoon: afternoon = Self.clamp(newValue)
            case .evening: evening = Self.clamp(newValue)
            }
        }
    }

    public mutating func adjust(_ bucket: BehavioralTimeOfDay, by delta: Double) {
        self[bucket] = self[bucket] + delta
    }

    public var mean: Double {
        (morning + afternoon + evening) / 3.0
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

// MARK: - Semantic hash

/// Stable identifier for a *class* of tasks (not a single instance).
public enum BehavioralSemanticHash {
    /// Prefer semantic type + normalized title stem; falls back to life area + title.
    public static func make(for task: LifeTask) -> String {
        let typeKey = task.semanticProfile?.semanticType.rawValue
            ?? task.lifeArea.rawValue
        let stem = normalizeToken(task.title)
        return "\(normalizeToken(typeKey))|\(stem)"
    }

    public static func make(taskID: String, title: String, semanticType: String? = nil) -> String {
        let typeKey = semanticType ?? "generic"
        let stemSource = title.isEmpty ? taskID : title
        return "\(normalizeToken(typeKey))|\(normalizeToken(stemSource))"
    }

    private static func normalizeToken(_ value: String) -> String {
        String(
            value
                .lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"\s+"#, with: "_", options: .regularExpression)
                .replacingOccurrences(of: #"[^a-z0-9_\-]"#, with: "", options: .regularExpression)
                .prefix(48)
        )
    }
}
