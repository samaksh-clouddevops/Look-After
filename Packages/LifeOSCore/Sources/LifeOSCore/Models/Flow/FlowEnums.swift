import Foundation

// MARK: - Flow Personality

/// UI temperament mode derived from energy score, sleep, and time of day.
/// Drives motion tempo, copy tone, and visual intensity on the Flow Canvas.
public enum FlowPersonality: String, Codable, Sendable, CaseIterable {
    /// Energy 0–35%. Slower motion, softer visuals, validating copy.
    case restore
    /// Energy 36–65%. Balanced defaults.
    case steady
    /// Energy 66–100%. Faster motion, vibrant visuals, confident copy.
    case peak

    /// Maps a normalized energy score (0.0–1.0) to a personality mode.
    public static func from(energyScore: Double) -> FlowPersonality {
        let clamped = min(max(energyScore, 0), 1)
        if clamped <= 0.35 { return .restore }
        if clamped <= 0.65 { return .steady }
        return .peak
    }
}

// MARK: - Flow Action Type

/// Describes the kind of hero action Flow Director recommends on the Flow Surface.
public enum FlowActionType: String, Codable, Sendable, CaseIterable {
    /// Resume an in-progress task.
    case `continue`
    /// Start a standard Flow session.
    case start
    /// Start a long deep-work session when energy and calendar align.
    case startDeep
    /// Start a short, low-friction session on low-energy days.
    case startSmall
    /// Offer a micro-chunk entry after repeated deferrals.
    case tryMicro
}

// MARK: - Coach Moment Type

/// Category of behavioral coaching chip shown on the Flow Surface.
public enum CoachMomentType: String, Codable, Sendable, CaseIterable {
    case microChunkOffer
    case playlistOffer
    case restSuggestion
    case deferralPattern
}

// MARK: - Environment Enums

/// Qualitative sleep assessment used by Environment Context fusion.
public enum SleepQuality: String, Codable, Sendable, CaseIterable {
    case poor
    case fair
    case good
    case excellent
    case unknown
}

/// Weather condition from WeatherKit, simplified for orchestration rules.
public enum WeatherCondition: String, Codable, Sendable, CaseIterable {
    case clear
    case cloudy
    case rain
    case snow
    case storm
    case unknown
}

/// Time-of-day bucket for briefing and personality adjustments.
public enum TimeOfDay: String, Codable, Sendable, CaseIterable {
    case morning    // 05:00–11:59
    case afternoon  // 12:00–16:59
    case evening    // 17:00–20:59
    case night      // 21:00–04:59

    public static func from(date: Date, calendar: Calendar = .current) -> TimeOfDay {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<12: return .morning
        case 12..<17: return .afternoon
        case 17..<21: return .evening
        default: return .night
        }
    }
}

/// Optional ambient noise level (permission-gated).
public enum NoiseLevel: String, Codable, Sendable, CaseIterable {
    case quiet
    case moderate
    case loud
    case unknown
}

/// Optional location context (permission-gated).
public enum LocationContext: String, Codable, Sendable, CaseIterable {
    case home
    case office
    case commute
    case grocery
    case other
    case unknown
}
