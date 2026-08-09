import Foundation
import LookAfterCore
import os

/// Drains `SyncOutboxStore` when the flag is on (Phase 2 WP 2.1).
///
/// Transport is injected so unit tests don't need Firestore.
public protocol SyncOutboxTransporting: Sendable {
    func apply(_ record: SyncOutboxRecord) async throws
}

/// No-op transport used until Firestore adapter is wired.
public struct NullSyncOutboxTransport: SyncOutboxTransporting {
    public init() {}
    public func apply(_ record: SyncOutboxRecord) async throws {}
}

@MainActor
public final class SyncOutboxWorker {

    public static let shared = SyncOutboxWorker()

    public static let maxAttempts = 8

    private let store: SyncOutboxStore
    private var transport: SyncOutboxTransporting
    private let logger = Logger(subsystem: "com.lookafter.app", category: "SyncOutboxWorker")
    private var drainTask: Task<Void, Never>?

    public init(store: SyncOutboxStore = .shared, transport: SyncOutboxTransporting = NullSyncOutboxTransport()) {
        self.store = store
        self.transport = transport
    }

    public func setTransport(_ transport: SyncOutboxTransporting) {
        self.transport = transport
    }

    /// Enqueue helper — no-ops when outbox flag is off (callers still do legacy push).
    public func enqueueTaskUpsert(userId: String, task: LifeTask) {
        guard ArchitectureFeatureFlags.useSyncOutbox else { return }
        guard !userId.isEmpty else { return }
        do {
            let data = try SharedFormatters.jsonEncoderSeconds.encode(task)
            try store.enqueue(
                SyncOutboxRecord(
                    userId: userId,
                    entityType: .task,
                    entityId: task.id,
                    operation: .upsert,
                    payloadJSON: data
                )
            )
        } catch {
            logger.error("enqueue upsert failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func enqueueTaskDelete(userId: String, taskId: String) {
        guard ArchitectureFeatureFlags.useSyncOutbox else { return }
        guard !userId.isEmpty, !taskId.isEmpty else { return }
        do {
            try store.enqueue(
                SyncOutboxRecord(
                    userId: userId,
                    entityType: .task,
                    entityId: taskId,
                    operation: .delete
                )
            )
        } catch {
            logger.error("enqueue delete failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func pendingCount(userId: String) -> Int {
        (try? store.pendingCount(userId: userId)) ?? 0
    }

    /// Drain ready items once. Safe to call from BG task or after reconnect.
    @discardableResult
    public func drainOnce(userId: String) async -> Int {
        guard ArchitectureFeatureFlags.useSyncOutbox else { return 0 }
        guard !userId.isEmpty else { return 0 }

        // Recover crash mid-flight.
        try? store.resetInFlightToPending(userId: userId)

        let batch: [SyncOutboxRecord]
        do {
            batch = try store.dequeueReady(userId: userId, limit: 20)
        } catch {
            logger.error("dequeue failed: \(error.localizedDescription, privacy: .public)")
            return 0
        }

        var success = 0
        for record in batch {
            do {
                try await transport.apply(record)
                try store.markSucceeded(id: record.id)
                success += 1
            } catch {
                let attempts = record.attempts + 1
                let dead = attempts >= Self.maxAttempts
                let delay = Self.backoffSeconds(attempt: attempts)
                try? store.markFailed(
                    id: record.id,
                    error: error.localizedDescription,
                    attempts: attempts,
                    nextAttemptAt: Date().addingTimeInterval(delay),
                    dead: dead
                )
                logger.error(
                    "outbox apply failed id=\(record.id, privacy: .public) attempts=\(attempts): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        return success
    }

    public func scheduleDrain(userId: String) {
        guard ArchitectureFeatureFlags.useSyncOutbox else { return }
        drainTask?.cancel()
        drainTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            _ = await self.drainOnce(userId: userId)
        }
    }

    public static func backoffSeconds(attempt: Int) -> TimeInterval {
        let exp = min(attempt, 6)
        return pow(2.0, Double(exp)) // 2,4,8,...,64
    }
}
