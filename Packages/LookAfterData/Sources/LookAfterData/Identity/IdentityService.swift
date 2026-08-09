import Foundation
import LookAfterCore

/// High-level identity for session lifecycle (Phase 1 WP 1.1).
public enum IdentityState: Equatable, Sendable {
    case signedOut
    /// Local/offline guest or mock auth — not a Firebase Auth UID.
    case offlineGuest(userId: String)
    /// Firebase Auth (or stable assigned cloud UID).
    case firebaseUser(userId: String, email: String?)

    public var userId: String? {
        switch self {
        case .signedOut: return nil
        case .offlineGuest(let id), .firebaseUser(let id, _): return id
        }
    }

    public var isAuthenticated: Bool {
        userId != nil
    }

    /// Safe to start user-scoped bootstrap (tasks, brain, health).
    public var isStableForBootstrap: Bool {
        switch self {
        case .signedOut: return false
        case .offlineGuest, .firebaseUser: return true
        }
    }
}

/// Read model over auth — SessionContainer and bootstrap depend on this, not FirebaseManager directly.
@MainActor
public protocol IdentityProviding: AnyObject {
    var state: IdentityState { get }
    /// Monotonic generation; increments on every identity transition.
    var generation: UInt64 { get }
    var resolvedUserId: String { get }
}

/// Default identity provider backed by `FirebaseManager`.
@MainActor
public final class IdentityService: ObservableObject, IdentityProviding {

    public static let shared = IdentityService()

    @Published public private(set) var state: IdentityState = .signedOut
    @Published public private(set) var generation: UInt64 = 0

    private let firebase: FirebaseManager
    private var pollTask: Task<Void, Never>?

    public init(firebase: FirebaseManager = .shared) {
        self.firebase = firebase
        refreshFromFirebase()
        startPolling()
    }

    public var resolvedUserId: String {
        state.userId ?? firebase.resolvedUserId
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Call after auth APIs or when app becomes active.
    public func refreshFromFirebase() {
        let next = Self.map(
            isAuthenticated: firebase.isAuthenticated,
            currentUserId: firebase.currentUserId,
            resolvedUserId: firebase.resolvedUserId,
            email: firebase.userEmail,
            cloudSyncAvailable: firebase.isCloudSyncAvailable
        )
        apply(next)
    }

    /// Test / SessionContainer seam.
    public func applyForTesting(_ newState: IdentityState) {
        apply(newState)
    }

    // MARK: - Mapping

    public static func map(
        isAuthenticated: Bool,
        currentUserId: String?,
        resolvedUserId: String,
        email: String?,
        cloudSyncAvailable: Bool
    ) -> IdentityState {
        guard isAuthenticated else { return .signedOut }

        let uid = (currentUserId?.isEmpty == false ? currentUserId! : resolvedUserId)
        guard !uid.isEmpty else { return .signedOut }

        // Synthetic offline ids from mock/guest auth.
        if uid.hasPrefix("guest_") || uid.hasPrefix("usr_") || !cloudSyncAvailable {
            return .offlineGuest(userId: uid)
        }
        return .firebaseUser(userId: uid, email: email)
    }

    private func apply(_ newState: IdentityState) {
        guard newState != state else { return }
        state = newState
        generation &+= 1
    }

    /// Lightweight poll — FirebaseManager is ObservableObject; full Combine bridge can replace this later.
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, !Task.isCancelled else { return }
                self.refreshFromFirebase()
            }
        }
    }
}
