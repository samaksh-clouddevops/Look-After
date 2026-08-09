import Foundation

/// Configuration for the Azure Container Apps auth + LLM proxy.
public struct AuthProxyConfiguration: Sendable, Equatable {
    public var baseURL: URL
    public var isEnabled: Bool

    public init(baseURL: URL, isEnabled: Bool = true) {
        self.baseURL = baseURL
        self.isEnabled = isEnabled
    }

    /// Reads `AuthProxyBaseURL` from Info.plist / main bundle, or `AUTH_PROXY_BASE_URL` env.
    public static func fromBundle(_ bundle: Bundle = .main) -> AuthProxyConfiguration? {
        if let env = ProcessInfo.processInfo.environment["AUTH_PROXY_BASE_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty,
           let url = URL(string: env) {
            return AuthProxyConfiguration(baseURL: url)
        }
        if let raw = bundle.object(forInfoDictionaryKey: "AuthProxyBaseURL") as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, let url = URL(string: trimmed) {
                return AuthProxyConfiguration(baseURL: url)
            }
        }
        return nil
    }
}

/// Provides a Firebase (or equivalent) ID token for proxy calls.
public protocol AuthProxyTokenProviding: Sendable {
    func idToken(forceRefresh: Bool) async throws -> String?
}

/// Local license gate used by `GLMService` to prefer the proxy.
public protocol LicenseStatusProviding: Sendable {
    var isLicensed: Bool { get }
}
