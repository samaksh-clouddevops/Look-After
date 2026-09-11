import Foundation
import Synchronization

/// Subsystem that participates in factory reset.
public protocol ResettableSubsystem: Sendable {
    var subsystemName: String { get }
    func resetLocal(userId: String) async
}

/// Keys preserved during factory reset (auth session and developer flags only).
public enum FactoryResetPreservation {
    public static let userDefaultsKeys: Set<String> = [
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
    private static let isActiveFlag = Mutex(false)

    public static var isActive: Bool {
        isActiveFlag.withLock { $0 }
    }

    public static func enter() {
        isActiveFlag.withLock { $0 = true }
    }

    public static func exit() {
        isActiveFlag.withLock { $0 = false }
    }
}
