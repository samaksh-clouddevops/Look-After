import Foundation

/// Subsystem that participates in factory reset.
public protocol ResettableSubsystem: Sendable {
    var subsystemName: String { get }
    func resetLocal(userId: String) async
}

/// Keys preserved during factory reset (API keys, auth session, developer flags only).
public enum FactoryResetPreservation {
    public static let userDefaultsKeys: Set<String> = [
        "glmKeyRecords",
        "glmConfiguration",
        "glmUsageRecords",
        FlowDirectorFeature.userDefaultsKey,
        "saved_user_uid",
        "userEmail",
        freshStartFlagKey,
    ]

    public static let freshStartFlagKey = "lifeos.pendingFreshStart"
}

/// Blocks Firestore merge / remote reload while factory reset cloud wipe is in progress.
public enum FreshInstallGuard: Sendable {
    private static let lock = NSLock()
    private static var _isActive = false

    public static var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isActive
    }

    public static func enter() {
        lock.lock()
        _isActive = true
        lock.unlock()
    }

    public static func exit() {
        lock.lock()
        _isActive = false
        lock.unlock()
    }
}
