import Foundation
import os
import LookAfterCore
import LookAfterData

/// Extracted bootstrap pipeline (Phase 4 WP 4.1).
///
/// Owns scheduling/cancellation metadata; work still executes via `BootstrapExecuting`
/// implemented by `AppShellState` until further service extraction.
@MainActor
final class BootstrapCoordinator {
    private(set) var bootstrappedUserId: String?
    private(set) var hasCompletedBootstrap = false
    private var bootstrapTask: Task<Void, Never>?
    private var launchSignpostID: OSSignpostID?

    weak var executor: BootstrapExecuting?

    func reset() {
        bootstrapTask?.cancel()
        bootstrapTask = nil
        bootstrappedUserId = nil
        hasCompletedBootstrap = false
        launchSignpostID = nil
    }

    func bootstrap(userId: String, healthSync: HealthSyncService, identity: IdentityService) {
        guard !userId.isEmpty else { return }
        guard let executor else { return }

        identity.refreshFromFirebase()
        let resolvedId = Self.resolveUserId(requested: userId, identity: identity)
        guard !resolvedId.isEmpty else { return }

        executor.attachSessionIfNeeded()

        if FactoryResetManager.shared.isPendingFreshStart {
            Task { await executor.bootstrapFreshStart(userId: resolvedId, healthSync: healthSync) }
            return
        }

        if bootstrappedUserId != resolvedId {
            bootstrapTask?.cancel()
            bootstrapTask = nil
            hasCompletedBootstrap = false
            bootstrappedUserId = resolvedId
        }

        if hasCompletedBootstrap, bootstrappedUserId == resolvedId { return }
        if let bootstrapTask, bootstrappedUserId == resolvedId, !bootstrapTask.isCancelled { return }

        let identityGeneration = identity.generation
        launchSignpostID = PerformanceSignposts.beginLaunchToBriefing()
        bootstrapTask = Task { [weak self] in
            guard let self else { return }
            await executor.runBootstrapWork(
                userId: resolvedId,
                healthSync: healthSync,
                identityGeneration: identityGeneration
            )
            if let launchSignpostID = self.launchSignpostID {
                PerformanceSignposts.endLaunchToBriefing(launchSignpostID)
                self.launchSignpostID = nil
            }
            if identity.generation == identityGeneration {
                self.hasCompletedBootstrap = true
            } else {
                self.hasCompletedBootstrap = false
                self.bootstrappedUserId = nil
            }
            self.bootstrapTask = nil
            SessionEventBus.shared.publish(.identityChanged(userId: resolvedId))
        }
    }

    private static func resolveUserId(requested: String, identity: IdentityService) -> String {
        if ArchitectureFeatureFlags.useSessionContainer,
           identity.state.isStableForBootstrap,
           let id = identity.state.userId,
           !id.isEmpty {
            return id
        }
        return requested
    }
}

/// Bridge so BootstrapCoordinator can call shell implementation without owning VMs yet.
@MainActor
protocol BootstrapExecuting: AnyObject {
    func attachSessionIfNeeded()
    func bootstrapFreshStart(userId: String, healthSync: HealthSyncService) async
    func runBootstrapWork(userId: String, healthSync: HealthSyncService, identityGeneration: UInt64) async
}
