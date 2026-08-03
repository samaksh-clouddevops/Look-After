import Foundation

/// Presentation mode — shared data layer, different navigation and UI shells.
public enum ExperienceMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case classic
    case aiExecutive

    public static let storageKey = "lifeos.experienceMode"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .aiExecutive: return "Companion"
        }
    }

    public var subtitle: String {
        switch self {
        case .classic: return "Module-based navigation with full LifeOS features"
        case .aiExecutive: return "Today-first layout with decisions, timeline, and profile"
        }
    }

    public static var current: ExperienceMode {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? ExperienceMode.classic.rawValue
        return ExperienceMode(rawValue: raw) ?? .classic
    }

    public static var isAIExecutiveEnabled: Bool {
        current == .aiExecutive
    }

    public static func save(_ mode: ExperienceMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: storageKey)
    }
}
