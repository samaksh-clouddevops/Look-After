import Foundation

/// Configuration for the official GLM 5.2 API.
public struct GLMConfiguration: Codable, Sendable, Equatable {
    public var baseURL: String
    public var defaultModel: String
    public var requestTimeoutSeconds: TimeInterval
    public var streamingEnabled: Bool

    public init(
        baseURL: String = GLMConfiguration.defaultBaseURL,
        defaultModel: String = GLMConfiguration.defaultModel,
        requestTimeoutSeconds: TimeInterval = 90,
        streamingEnabled: Bool = true
    ) {
        self.baseURL = baseURL
        self.defaultModel = defaultModel
        self.requestTimeoutSeconds = requestTimeoutSeconds
        self.streamingEnabled = streamingEnabled
    }

    public static let defaultBaseURL = "https://api.z.ai/api/paas/v4"
    public static let defaultModel = "glm-5.2"
    public static let apiKeyEnvVar = "GLM_API_KEY"
    public static let legacyEnvVar = "ZAI_API_KEY"

    /// Built-in GLM key used on first launch when the user has not added their own.
    /// Users can replace or remove it in Settings → API Keys.
    public static let bundledDefaultAPIKey = "4051d0ad6e6d4191b695384d5d44ab3f.mvzJ0P6ZgwjUSN4C"

    public static let `default` = GLMConfiguration()

    public var chatCompletionsURL: String {
        baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions"
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
    public var dailyTotalUSD: Double
    public var monthlyTotalUSD: Double
    public var recentRecords: [GLMUsageRecord]

    public init(
        dailyRequestCount: Int = 0,
        monthlyRequestCount: Int = 0,
        dailyTotalUSD: Double = 0,
        monthlyTotalUSD: Double = 0,
        recentRecords: [GLMUsageRecord] = []
    ) {
        self.dailyRequestCount = dailyRequestCount
        self.monthlyRequestCount = monthlyRequestCount
        self.dailyTotalUSD = dailyTotalUSD
        self.monthlyTotalUSD = monthlyTotalUSD
        self.recentRecords = recentRecords
    }
}
