import Foundation

/// Remote APNs requires the `aps-environment` entitlement (paid Apple Developer Program).
/// Local `UNUserNotificationCenter` scheduling works without it.
enum PushCapabilities {
    /// True when the signed app includes the APNs entitlement.
    /// - Device debug builds: reads `embedded.mobileprovision`.
    /// - App Store / Release: set `REMOTE_PUSH_ENABLED=1` in build settings when shipping with FCM.
    static var hasRemotePushEntitlement: Bool {
        #if REMOTE_PUSH_ENABLED
        return true
        #else
        return provisioningProfileIncludesPushEntitlement
        #endif
    }

    private static var provisioningProfileIncludesPushEntitlement: Bool {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let profile = String(data: data, encoding: .isoLatin1) else {
            return false
        }
        return profile.contains("aps-environment")
    }
}
