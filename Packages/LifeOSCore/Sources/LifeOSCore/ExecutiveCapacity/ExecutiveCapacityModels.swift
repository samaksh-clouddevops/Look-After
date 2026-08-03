import Foundation

/// Dynamic capacity band — never expose raw percentages in UI by default.
public enum ExecutiveCapacityBand: String, Codable, Sendable, CaseIterable {
    case peakFocus
    case goodCapacity
    case moderateCapacity
    case lowCapacity
    case recoveryMode

    public var displayLabel: String {
        switch self {
        case .peakFocus: return "Peak Focus"
        case .goodCapacity: return "Good Capacity"
        case .moderateCapacity: return "Moderate Capacity"
        case .lowCapacity: return "Low Capacity"
        case .recoveryMode: return "Recovery Mode"
        }
    }

    public var tagline: String {
        switch self {
        case .peakFocus: return "Perfect for difficult thinking."
        case .goodCapacity: return "Good for meaningful work."
        case .moderateCapacity: return "Good for planning and admin."
        case .lowCapacity: return "Prefer errands and simple tasks."
        case .recoveryMode: return "Protect tomorrow."
        }
    }

    public var shortLabel: String {
        switch self {
        case .peakFocus: return "Peak"
        case .goodCapacity: return "Good"
        case .moderateCapacity: return "Moderate"
        case .lowCapacity: return "Low"
        case .recoveryMode: return "Recovery"
        }
    }
}

public struct CapacityForecastPoint: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var timeLabel: String
    public var band: ExecutiveCapacityBand

    public init(id: String = UUID().uuidString, timeLabel: String, band: ExecutiveCapacityBand) {
        self.id = id
        self.timeLabel = timeLabel
        self.band = band
    }
}

public struct CapacityReasoning: Codable, Sendable, Equatable {
    public var reasons: [String]
    public var recommendedWorkTypes: [String]
    public var avoidWorkTypes: [String]
    public var detailSummary: String?

    public init(
        reasons: [String] = [],
        recommendedWorkTypes: [String] = [],
        avoidWorkTypes: [String] = [],
        detailSummary: String? = nil
    ) {
        self.reasons = Array(reasons.prefix(3))
        self.recommendedWorkTypes = recommendedWorkTypes
        self.avoidWorkTypes = avoidWorkTypes
        self.detailSummary = detailSummary
    }
}

/// Brain output — UI renders this only; never computes capacity locally.
public struct ExecutiveCapacityState: Codable, Sendable, Equatable {
    public var band: ExecutiveCapacityBand
    public var confidence: Double
    public var reasoning: CapacityReasoning
    public var forecast: [CapacityForecastPoint]
    public var calculatedAt: Date

    public init(
        band: ExecutiveCapacityBand,
        confidence: Double,
        reasoning: CapacityReasoning,
        forecast: [CapacityForecastPoint] = [],
        calculatedAt: Date = Date()
    ) {
        self.band = band
        self.confidence = min(max(confidence, 0), 1)
        self.reasoning = reasoning
        self.forecast = forecast
        self.calculatedAt = calculatedAt
    }

    public static let moderate = ExecutiveCapacityState(
        band: .moderateCapacity,
        confidence: 0.6,
        reasoning: CapacityReasoning(
            reasons: ["Still learning your day."],
            recommendedWorkTypes: ["Light planning"],
            avoidWorkTypes: ["Deep complex work"]
        )
    )
}

/// Inputs for Executive Capacity inference — aggregated LifeState signals.
public struct ExecutiveCapacityInput: Sendable {
    public var snapshot: LifeContextSnapshot?
    public var healthSummary: HealthSummary?
    public var cognitiveSnapshot: CognitiveSnapshot?
    public var completedTodayCount: Int
    public var activeTaskCount: Int
    public var meetingCountHint: Int
    public var isInFlowSession: Bool
    public var weatherSummary: String?
    public var now: Date

    public init(
        snapshot: LifeContextSnapshot? = nil,
        healthSummary: HealthSummary? = nil,
        cognitiveSnapshot: CognitiveSnapshot? = nil,
        completedTodayCount: Int = 0,
        activeTaskCount: Int = 0,
        meetingCountHint: Int = 0,
        isInFlowSession: Bool = false,
        weatherSummary: String? = nil,
        now: Date = Date()
    ) {
        self.snapshot = snapshot
        self.healthSummary = healthSummary
        self.cognitiveSnapshot = cognitiveSnapshot
        self.completedTodayCount = completedTodayCount
        self.activeTaskCount = activeTaskCount
        self.meetingCountHint = meetingCountHint
        self.isInFlowSession = isInFlowSession
        self.weatherSummary = weatherSummary
        self.now = now
    }
}
