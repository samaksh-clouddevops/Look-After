import Testing
import Foundation
@testable import LookAfterData
import LookAfterAI

@MainActor
struct LicenseManagerSwiftTestingTests {
    @Test
    func redeemWithoutProxyThrowsNotConfigured() async {
        let manager = LicenseManager.shared
        manager.configure(proxyClient: nil)
        manager.clearLocalLicense()
        do {
            try await manager.redeem(productKey: "00000000-0000-0000-0000-000000000000")
            Issue.record("Expected AuthProxyError.notConfigured")
        } catch let error as AuthProxyError {
            guard case .notConfigured = error else {
                Issue.record("Unexpected AuthProxyError: \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(manager.isLicensed == false)
    }

    @Test
    func clearLocalLicenseClearsUserDefaultsCache() {
        let manager = LicenseManager.shared
        UserDefaults.standard.set(true, forKey: "lookafter.license.active")
        UserDefaults.standard.set("2026-01-01", forKey: "lookafter.license.redeemedAt")
        manager.clearLocalLicense()
        #expect(manager.isLicensed == false)
        #expect(UserDefaults.standard.bool(forKey: "lookafter.license.active") == false)
        #expect(UserDefaults.standard.string(forKey: "lookafter.license.redeemedAt") == nil)
    }
}
