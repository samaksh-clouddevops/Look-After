import Foundation
import LookAfterAI

/// Persists license status and talks to the Azure auth-proxy redeem/status APIs.
///
/// `UserDefaults` `isLicensed` is a **local cache only** — spoofable offline. Cloud AI must
/// still be gated by auth-proxy (403 when inactive). Call `refreshStatus()` on foreground /
/// launch when a proxy client is configured; do not treat the UD bool as source of truth.
@MainActor
public final class LicenseManager: ObservableObject {
    public static let shared = LicenseManager()

    private enum Keys {
        static let isLicensed = "lookafter.license.active"
        static let redeemedAt = "lookafter.license.redeemedAt"
        static let lastCheckedAt = "lookafter.license.lastCheckedAt"
    }

    @Published public private(set) var isLicensed: Bool
    @Published public private(set) var redeemedAt: String?
    @Published public private(set) var lastError: String?
    @Published public private(set) var isBusy: Bool = false

    public private(set) var proxyClient: AuthProxyClient?

    private init() {
        self.isLicensed = UserDefaults.standard.bool(forKey: Keys.isLicensed)
        self.redeemedAt = UserDefaults.standard.string(forKey: Keys.redeemedAt)
    }

    public func configure(proxyClient: AuthProxyClient?) {
        self.proxyClient = proxyClient
        GLMService.shared.authProxyClient = proxyClient
        GLMService.shared.licenseStatusProvider = LicenseStatusBridge()
    }

    public func clearLocalLicense() {
        isLicensed = false
        redeemedAt = nil
        UserDefaults.standard.removeObject(forKey: Keys.isLicensed)
        UserDefaults.standard.removeObject(forKey: Keys.redeemedAt)
    }

    public func redeem(productKey: String) async throws {
        guard let proxyClient else { throw AuthProxyError.notConfigured }
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        do {
            let result = try await proxyClient.redeem(productKey: productKey)
            apply(active: result.active, redeemedAt: ISO8601DateFormatter().string(from: Date()))
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    public func refreshStatus() async {
        guard let proxyClient else { return }
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        do {
            let status = try await proxyClient.licenseStatus()
            apply(active: status.active, redeemedAt: status.redeemedAt)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func apply(active: Bool, redeemedAt: String?) {
        isLicensed = active
        self.redeemedAt = redeemedAt
        UserDefaults.standard.set(active, forKey: Keys.isLicensed)
        if let redeemedAt {
            UserDefaults.standard.set(redeemedAt, forKey: Keys.redeemedAt)
        }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Keys.lastCheckedAt)
    }
}

/// Thread-safe bridge so `GLMService` can read license state without hopping to MainActor.
private struct LicenseStatusBridge: LicenseStatusProviding {
    var isLicensed: Bool {
        UserDefaults.standard.bool(forKey: "lookafter.license.active")
    }
}
