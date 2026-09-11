import Foundation

/// Configuration for the official Z.ai GLM API (premium default: GLM-5.3).
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
    public static let defaultModel = "glm-5.3"
    /// Previous premium id — migrated to `defaultModel` on load.
    public static let legacyPremiumModel = "glm-5.2"
    public static let defaultStandardModel = "glm-5.3"
    /// Previous standard id — migrated on load.
    public static let legacyStandardModel = "glm-4.7"
    public static let defaultEconomyModel = "glm-5.3-flash"
    /// Previous economy / flash fallback id — migrated on load.
    public static let legacyEconomyModel = "glm-4.7-flash"
    public static let apiKeyEnvVar = "GLM_API_KEY"
    public static let legacyEnvVar = "ZAI_API_KEY"

    /// Optional built-in GLM key for local development only — leave empty in source control.
    /// Users add their own key in Settings → API Keys, or set `GLM_API_KEY` in the environment.
    public static let bundledDefaultAPIKey = ""

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
    public static let flashFallbackModel = "glm-5.3-flash"

    /// Models to try for one tier — e.g. glm-5.3 then glm-5.3-flash.
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
        if normalized.contains("glm-5") || normalized.contains("5.3") || normalized.contains("5.2")
            || normalized.contains("5.1") || normalized.contains("5-turbo") {
            return true
        }
        return normalized == "glm-4.7"
    }

    /// GLM-5.3+ rejects `thinking.type: disabled` — reasoning is always on.
    public static func requiresMandatoryThinking(_ model: String) -> Bool {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let minor = glm5MinorVersion(normalized) else { return false }
        return minor >= 3
    }

    /// Lightweight reasoning for app chat/planning (Z.ai migration guidance for former `disabled` callers).
    public static let defaultReasoningEffort = "low"

    private static func glm5MinorVersion(_ normalizedModel: String) -> Int? {
        guard let range = normalizedModel.range(of: #"glm-5\.(\d+)"#, options: .regularExpression) else {
            return nil
        }
        let match = String(normalizedModel[range])
        guard let dot = match.lastIndex(of: "."),
              let minor = Int(match[match.index(after: dot)...]) else {
            return nil
        }
        return minor
    }

    /// Migrates persisted model ids when they still point at previous defaults.
    public mutating func migrateLegacyModelsIfNeeded() -> Bool {
        var changed = false
        let premium = defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if premium.caseInsensitiveCompare(Self.legacyPremiumModel) == .orderedSame {
            defaultModel = Self.defaultModel
            changed = true
        }
        let standard = standardModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if standard.caseInsensitiveCompare(Self.legacyStandardModel) == .orderedSame {
            standardModel = Self.defaultStandardModel
            changed = true
        }
        let economy = economyModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if economy.caseInsensitiveCompare(Self.legacyEconomyModel) == .orderedSame {
            economyModel = Self.defaultEconomyModel
            changed = true
        }
        return changed
    }

    /// Migrates a persisted premium model id when it still points at the previous flagship.
    public mutating func migrateLegacyPremiumModelIfNeeded() -> Bool {
        migrateLegacyModelsIfNeeded()
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
