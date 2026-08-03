import Foundation

/// User-friendly focus window — mapped internally to peak hours for scheduling.
public enum FocusTimePreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case earlyMorning = "Early morning (around 6–9 AM)"
    case lateMorning = "Late morning (around 9 AM–12 PM)"
    case afternoon = "Afternoon (around 12–3 PM)"
    case evening = "Evening (around 5–8 PM)"
    case notSure = "I'm not sure — infer from my profile"

    public var id: String { rawValue }

    public var label: String { rawValue }

    public var peakStartHour: Int {
        switch self {
        case .earlyMorning: return 6
        case .lateMorning: return 9
        case .afternoon: return 12
        case .evening: return 17
        case .notSure: return 9
        }
    }

    public var peakEndHour: Int {
        switch self {
        case .earlyMorning: return 9
        case .lateMorning: return 12
        case .afternoon: return 15
        case .evening: return 20
        case .notSure: return 12
        }
    }

    public var schedulingHint: String {
        switch self {
        case .earlyMorning: return "User focuses best early in the morning."
        case .lateMorning: return "User focuses best in the late morning."
        case .afternoon: return "User focuses best in the afternoon."
        case .evening: return "User focuses best in the evening."
        case .notSure: return "Focus window inferred from profile text."
        }
    }

    /// Infer from natural language in the profile.
    public static func infer(from text: String) -> FocusTimePreference? {
        let lower = text.lowercased()
        if lower.contains("early morning") || lower.contains("morning person")
            || lower.contains("before breakfast") || lower.contains("first thing") {
            return .earlyMorning
        }
        if lower.contains("before lunch") || lower.contains("late morning")
            || lower.contains("mid-morning") || lower.contains("deep work in the morning")
            || lower.contains("mornings for deep") || lower.contains("best in the morning") {
            return .lateMorning
        }
        if lower.contains("afternoon") && !lower.contains("afternoon slump") {
            return .afternoon
        }
        if lower.contains("evening") || lower.contains("night owl") || lower.contains("after work") {
            return .evening
        }
        return nil
    }
}
