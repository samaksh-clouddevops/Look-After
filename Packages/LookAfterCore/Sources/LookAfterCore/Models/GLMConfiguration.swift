import Foundation

/// Configuration for the official GLM 5.2 API.
public struct GLMConfiguration: Codable, Sendable, Equatable {
    public var baseURL: String
    /// Premium-tier model (coach, planning, replan).
    public var defaultModel: String
    public var standardModel: String
    public var economyModel: String
    public var tieredRoutingEnabled: Bool
    public var requestTimeoutSeconds: TimeInterval
    public var streamingEnabled: Bool

    public init(
        baseURL: String = GLMConfiguration.defaultBaseURL,
        defaultModel: String = GLMConfiguration.defaultModel,
        standardModel: String = GLMConfiguration.defaultStandardModel,
        economyModel: String = GLMConfiguration.defaultEconomyModel,
        tieredRoutingEnabled: Bool = true,
        requestTimeoutSeconds: TimeInterval = 90,
        streamingEnabled: Bool = true
    ) {
        self.baseURL = baseURL
        self.defaultModel = defaultModel
        self.standardModel = standardModel
        self.economyModel = economyModel
        self.tieredRoutingEnabled = tieredRoutingEnabled
        self.requestTimeoutSeconds = requestTimeoutSeconds
        self.streamingEnabled = streamingEnabled
    }

    public static let defaultBaseURL = "https://api.z.ai/api/paas/v4"
    public static let defaultModel = "glm-5.2"
    public static let defaultStandardModel = "glm-4.7"
    public static let defaultEconomyModel = "glm-4.7-flash"
    public static let apiKeyEnvVar = "GLM_API_KEY"
    public static let legacyEnvVar = "ZAI_API_KEY"

    /// Built-in GLM key used on first launch when the user has not added their own.
    /// Users can replace or remove it in Settings → API Keys.
    public static let bundledDefaultAPIKey = "4051d0ad6e6d4191b695384d5d44ab3f.mvzJ0P6ZgwjUSN4C"

    enum CodingKeys: String, CodingKey {
        case baseURL, defaultModel, standardModel, economyModel, tieredRoutingEnabled
        case requestTimeoutSeconds, streamingEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? Self.defaultBaseURL
        defaultModel = try container.decodeIfPresent(String.self, forKey: .defaultModel) ?? Self.defaultModel
        standardModel = try container.decodeIfPresent(String.self, forKey: .standardModel) ?? Self.defaultStandardModel
        economyModel = try container.decodeIfPresent(String.self, forKey: .economyModel) ?? Self.defaultEconomyModel
        tieredRoutingEnabled = try container.decodeIfPresent(Bool.self, forKey: .tieredRoutingEnabled) ?? true
        requestTimeoutSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .requestTimeoutSeconds) ?? 90
        streamingEnabled = try container.decodeIfPresent(Bool.self, forKey: .streamingEnabled) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(defaultModel, forKey: .defaultModel)
        try container.encode(standardModel, forKey: .standardModel)
        try container.encode(economyModel, forKey: .economyModel)
        try container.encode(tieredRoutingEnabled, forKey: .tieredRoutingEnabled)
        try container.encode(requestTimeoutSeconds, forKey: .requestTimeoutSeconds)
        try container.encode(streamingEnabled, forKey: .streamingEnabled)
    }

    public static let `default` = GLMConfiguration()

    public var chatCompletionsURL: String {
        baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions"
    }

    /// Resolves the API model id for a tier. When routing is off, always returns the premium model.
    public func model(for tier: AIModelTier) -> String {
        guard tieredRoutingEnabled else { return defaultModel }
        switch tier {
        case .premium: return defaultModel
        case .standard: return standardModel
        case .economy: return economyModel
        }
    }

    /// Tiers to attempt in order when a cheaper call fails or returns empty content.
    public func fallbackTiers(startingAt tier: AIModelTier) -> [AIModelTier] {
        guard tieredRoutingEnabled else { return [.premium] }
        switch tier {
        case .economy: return [.economy]
        case .standard: return [.standard, .economy]
        case .premium: return [.premium, .economy]
        }
    }

    /// Universal flash fallback when a premium / standard GLM model is unavailable.
    public static let flashFallbackModel = "glm-4.7-flash"

    /// Models to try for one tier — e.g. glm-5.2 then glm-4.7-flash.
    public func modelsToAttempt(primary: String) -> [String] {
        guard Self.usesFlashFallback(primary) else { return [primary] }
        let flash = economyModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.defaultEconomyModel
            : economyModel
        if primary.caseInsensitiveCompare(flash) == .orderedSame { return [primary] }
        return [primary, flash]
    }

    /// True for GLM 5.x and glm-4.7 — not already a flash model.
    public static func usesFlashFallback(_ model: String) -> Bool {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        if normalized.contains("flash") { return false }
        if normalized.contains("glm-5") || normalized.contains("5.2")
            || normalized.contains("5.1") || normalized.contains("5-turbo") {
            return true
        }
        return normalized == "glm-4.7"
    }
}

public struct GLMUsageRecord: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var timestamp: Date
    public var model: String
    public var promptTokens: Int
    public var completionTokens: Int
    public var estimatedCostUSD: Double
    public var latencyMs: Int
    public var success: Bool
    public var failureReason: String?

    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        model: String,
        promptTokens: Int = 0,
        completionTokens: Int = 0,
        estimatedCostUSD: Double = 0,
        latencyMs: Int = 0,
        success: Bool = true,
        failureReason: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.model = model
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.estimatedCostUSD = estimatedCostUSD
        self.latencyMs = latencyMs
        self.success = success
        self.failureReason = failureReason
    }
}

public struct GLMUsageSummary: Sendable, Equatable {
    public var dailyRequestCount: Int
    public var monthlyRequestCount: Int
    public var dailyPromptTokens: Int
    public var dailyCompletionTokens: Int
    public var dailyTotalTokens: Int
    public var monthlyPromptTokens: Int
    public var monthlyCompletionTokens: Int
    public var monthlyTotalTokens: Int
    public var dailyTotalUSD: Double
    public var monthlyTotalUSD: Double
    public var recentRecords: [GLMUsageRecord]

    public init(
        dailyRequestCount: Int = 0,
        monthlyRequestCount: Int = 0,
        dailyPromptTokens: Int = 0,
        dailyCompletionTokens: Int = 0,
        dailyTotalTokens: Int = 0,
        monthlyPromptTokens: Int = 0,
        monthlyCompletionTokens: Int = 0,
        monthlyTotalTokens: Int = 0,
        dailyTotalUSD: Double = 0,
        monthlyTotalUSD: Double = 0,
        recentRecords: [GLMUsageRecord] = []
    ) {
        self.dailyRequestCount = dailyRequestCount
        self.monthlyRequestCount = monthlyRequestCount
        self.dailyPromptTokens = dailyPromptTokens
        self.dailyCompletionTokens = dailyCompletionTokens
        self.dailyTotalTokens = dailyTotalTokens
        self.monthlyPromptTokens = monthlyPromptTokens
        self.monthlyCompletionTokens = monthlyCompletionTokens
        self.monthlyTotalTokens = monthlyTotalTokens
        self.dailyTotalUSD = dailyTotalUSD
        self.monthlyTotalUSD = monthlyTotalUSD
        self.recentRecords = recentRecords
    }

    /// Compact display for large token counts (e.g. 12.4K, 1.2M).
    public static func formatTokenCount(_ count: Int) -> String {
        let value = Double(count)
        switch count {
        case 1_000_000...:
            return String(format: "%.1fM", value / 1_000_000)
        case 10_000...:
            return String(format: "%.1fK", value / 1_000)
        default:
            return count.formatted()
        }
    }
}
