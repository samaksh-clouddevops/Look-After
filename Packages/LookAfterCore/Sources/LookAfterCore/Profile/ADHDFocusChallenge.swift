import Foundation

/// Canonical ADHD focus challenge — single storage key and picker tags app-wide.
public enum ADHDFocusChallenge: String, CaseIterable, Identifiable, Sendable, Codable {
    case taskInitiation
    case timeBlindness
    case hyperfocus
    case overwhelm
    case workingMemory
    case emotionalRegulation

    public static let storageKey = "adhdFocusChallenge"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .taskInitiation: return "Task initiation"
        case .timeBlindness: return "Time blindness"
        case .hyperfocus: return "Hyperfocus"
        case .overwhelm: return "Overwhelm"
        case .workingMemory: return "Working memory"
        case .emotionalRegulation: return "Emotional regulation"
        }
    }

    public static var defaultValue: ADHDFocusChallenge { .taskInitiation }

    /// Reads UserDefaults, migrating legacy onboarding/settings strings.
    public static func load(from defaults: UserDefaults = .standard) -> ADHDFocusChallenge {
        guard let stored = defaults.string(forKey: storageKey) else { return defaultValue }
        return resolve(stored)
    }

    /// Maps any previously stored label to the canonical case.
    public static func resolve(_ stored: String) -> ADHDFocusChallenge {
        if let exact = ADHDFocusChallenge(rawValue: stored) { return exact }

        switch stored.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "task initiation":
            return .taskInitiation
        case "time blindness":
            return .timeBlindness
        case "hyperfocus", "hyperfocus context switching":
            return .hyperfocus
        case "overwhelm", "task paralysis / overwhelm":
            return .overwhelm
        case "working memory":
            return .workingMemory
        case "emotional regulation":
            return .emotionalRegulation
        default:
            return defaultValue
        }
    }

    public func persist(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.storageKey)
    }

    /// Normalizes a legacy stored value to the canonical raw value if needed.
    @discardableResult
    public static func normalizeStorage(in defaults: UserDefaults = .standard) -> ADHDFocusChallenge {
        let resolved = load(from: defaults)
        resolved.persist(to: defaults)
        return resolved
    }
}
