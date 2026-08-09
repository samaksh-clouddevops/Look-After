import Foundation
import LookAfterCore

/// Per-user composition root (Phase 1 WP 1.2).
///
/// Built only when identity is stable for bootstrap. AppShellState should hold this
/// instead of grabbing every `.shared` service ad hoc (gated by `useSessionContainer`).
@MainActor
public final class SessionContainer {

    public let identity: IdentityProviding
    public let identityGenerationAtStart: UInt64
    public let userId: String
    public let taskStore: TaskStore
    public let inboxStore: InboxSQLiteStore
    public let outboxStore: SyncOutboxStore
    /// Scaffold brain entry (Phase 3); swap primary backend when Flow/LLM adapters land.
    public let brainFacade: any BrainFacadeProtocol
    public let createdAt: Date

    private var tornDown = false
    private var tasks: [Task<Void, Never>] = []

    public var isTornDown: Bool { tornDown }

    public init(
        identity: IdentityProviding,
        taskStore: TaskStore = .shared,
        inboxStore: InboxSQLiteStore = .shared,
        outboxStore: SyncOutboxStore = .shared,
        brainFacade: (any BrainFacadeProtocol)? = nil
    ) {
        self.identity = identity
        self.identityGenerationAtStart = identity.generation
        self.userId = identity.resolvedUserId
        self.taskStore = taskStore
        self.inboxStore = inboxStore
        self.outboxStore = outboxStore
        self.brainFacade = brainFacade
            ?? BrainFacadeRouter(primary: DeterministicBrainFacadeBackend())
        self.createdAt = Date()
    }

    /// Returns nil when identity is not ready (signed out / empty uid).
    public static func makeIfReady(
        identity: IdentityProviding = IdentityService.shared,
        taskStore: TaskStore = .shared,
        requireFlag: Bool = true
    ) -> SessionContainer? {
        if requireFlag, !ArchitectureFeatureFlags.useSessionContainer {
            return nil
        }
        guard identity.state.isStableForBootstrap else { return nil }
        let uid = identity.resolvedUserId
        guard !uid.isEmpty else { return nil }
        return SessionContainer(identity: identity, taskStore: taskStore)
    }

    /// Identity changed under us — bootstrap should abort/restart.
    public var isIdentityStale: Bool {
        identity.generation != identityGenerationAtStart
            || identity.resolvedUserId != userId
            || !identity.state.isStableForBootstrap
    }

    public func addManagedTask(_ task: Task<Void, Never>) {
        tasks.append(task)
    }

    /// Cancel work and mark unusable (sign-out / factory reset).
    public func tearDown() {
        guard !tornDown else { return }
        tornDown = true
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }
}
