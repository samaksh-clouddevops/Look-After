import Foundation

/// Domain events for Session-scoped subscribers (Phase 5 / ADR path).
public enum SessionEvent: Sendable, Equatable {
    case tasksChanged(userId: String)
    case scheduleChanged(userId: String)
    case identityChanged(userId: String?)
    case focusEnded(userId: String)
    case healthSynced(userId: String)
    case outboxDrained(userId: String, successCount: Int)
    case custom(name: String)
}

/// Lightweight in-process pub/sub. Dual-publishes to NotificationCenter when flag is on.
public final class SessionEventBus: @unchecked Sendable {

    public static let shared = SessionEventBus()

    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<SessionEvent>.Continuation] = [:]

    public init() {}

    public func subscribe() -> AsyncStream<SessionEvent> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.lock.lock()
                self?.continuations[id] = nil
                self?.lock.unlock()
            }
        }
    }

    public func publish(_ event: SessionEvent) {
        lock.lock()
        let snaps = Array(continuations.values)
        lock.unlock()
        for cont in snaps {
            cont.yield(event)
        }

        guard ArchitectureFeatureFlags.useTypedEventBus else { return }
        // Dual-publish legacy NotificationCenter for gradual migration.
        switch event {
        case .tasksChanged:
            NotificationCenter.default.post(name: .taskListDidChange, object: nil)
        case .scheduleChanged:
            NotificationCenter.default.post(name: .scheduleDidChange, object: nil)
        case .healthSynced:
            NotificationCenter.default.post(
                name: .analyticsDataDidChange,
                object: nil,
                userInfo: ["reason": AnalyticsDataChangeReason.healthSyncCompleted.rawValue]
            )
        case .focusEnded:
            NotificationCenter.default.post(
                name: .analyticsDataDidChange,
                object: nil,
                userInfo: ["reason": AnalyticsDataChangeReason.focusSessionEnded.rawValue]
            )
        case .identityChanged, .outboxDrained, .custom:
            break
        }
    }

    /// Call from existing NotificationCenter posts when flag is on (dual-path entry).
    public func publishFromLegacyTaskListChange(userId: String = "") {
        guard ArchitectureFeatureFlags.useTypedEventBus else { return }
        // Avoid loops: only yield to stream subscribers, don't re-post Notification.
        lock.lock()
        let snaps = Array(continuations.values)
        lock.unlock()
        for cont in snaps {
            cont.yield(.tasksChanged(userId: userId))
        }
    }
}
