import Foundation

/// Metadata for a stored GLM API key. Secrets live only in the Keychain.
public struct GLMKeyRecord: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var isEnabled: Bool
    public var sortOrder: Int
    public var maskedSuffix: String
    public var isDefault: Bool
    public var lastSuccessfulRequest: Date?
    public var lastFailure: Date?
    public var lastFailureReason: String?
    public var consecutiveFailures: Int
    public var exhaustedUntil: Date?
    public var lastUsedAt: Date?

    public init(
        id: String = UUID().uuidString,
        name: String,
        isEnabled: Bool = true,
        sortOrder: Int = 0,
        maskedSuffix: String = "****",
        isDefault: Bool = false,
        lastSuccessfulRequest: Date? = nil,
        lastFailure: Date? = nil,
        lastFailureReason: String? = nil,
        consecutiveFailures: Int = 0,
        exhaustedUntil: Date? = nil,
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
        self.maskedSuffix = maskedSuffix
        self.isDefault = isDefault
        self.lastSuccessfulRequest = lastSuccessfulRequest
        self.lastFailure = lastFailure
        self.lastFailureReason = lastFailureReason
        self.consecutiveFailures = consecutiveFailures
        self.exhaustedUntil = exhaustedUntil
        self.lastUsedAt = lastUsedAt
    }

    public var status: GLMKeyStatus {
        if !isEnabled { return .disabled }
        if let exhaustedUntil, exhaustedUntil > Date() { return .exhausted }
        if consecutiveFailures >= 3 { return .failing }
        return .active
    }

    public var maskedDisplay: String {
        "************\(maskedSuffix)"
    }
}

public enum GLMKeyStatus: String, Sendable {
    case active
    case disabled
    case exhausted
    case failing

    public var iconName: String {
        switch self {
        case .active: return "checkmark.circle.fill"
        case .disabled: return "xmark.circle.fill"
        case .exhausted: return "clock.badge.exclamationmark.fill"
        case .failing: return "exclamationmark.triangle.fill"
        }
    }

    public var label: String {
        switch self {
        case .active: return "Active"
        case .disabled: return "Disabled"
        case .exhausted: return "Quota exhausted"
        case .failing: return "Repeated failures"
        }
    }
}

public enum GLMServiceError: Error, LocalizedError {
    case allKeysExhausted
    case noKeysConfigured
    case keyNotFound
    case invalidAPIKey
    case quotaExceeded
    case rateLimited
    case networkError(String)
    case parseError(String)

    public var errorDescription: String? {
        switch self {
        case .allKeysExhausted:
            return "All configured GLM API keys have reached their quota or are temporarily unavailable."
        case .noKeysConfigured:
            return "No GLM API key configured. Add one in Settings → API Keys."
        case .keyNotFound:
            return "API key not found."
        case .invalidAPIKey:
            return "GLM API key is missing or invalid."
        case .quotaExceeded:
            return "GLM quota or rate limit exceeded."
        case .rateLimited:
            return "GLM rate limit reached."
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .parseError(let msg):
            return "Failed to parse GLM response: \(msg)"
        }
    }
}
