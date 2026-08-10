import Foundation
import LookAfterCore

/// Abstraction for Firebase App Check (Phase 6.4).
///
/// Production implementation will wrap `AppCheck.appCheck().token()`.
/// Until Firebase App Check SDK is linked and providers configured, returns nil.
public protocol AppCheckTokenProviding: Sendable {
    func currentToken() async -> String?
}

/// No-op provider — safe default.
public struct NullAppCheckTokenProvider: AppCheckTokenProviding {
    public init() {}
    public func currentToken() async -> String? { nil }
}

/// Header name expected by auth-proxy when App Check enforcement is enabled.
public enum AppCheckHTTP {
    public static let headerName = "X-Firebase-AppCheck"
}

/// Holds the process-wide provider for AuthProxyClient injection.
@MainActor
public enum AppCheckConfiguration {
    public static var provider: any AppCheckTokenProviding = NullAppCheckTokenProvider()
}
