import Foundation
import LookAfterData
import Network
import os

/// Persists capture requests when offline and drains the queue when connectivity returns.
@MainActor
public final class CaptureOfflineQueue {
    public static let shared = CaptureOfflineQueue()

    /// Hard cap — oldest entries drop first when exceeded (R-028 / BUG-016).
    public static let maxPendingCaptures = 100

    private struct PendingCapture: Codable, Identifiable {
        var id: String
        var request: CaptureRequest
        var userId: String
        var queuedAt: Date
    }

    private let persistence = LocalPersistenceManager.shared
    private let filename = "pending_captures"
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.lookafter.capture.connectivity")
    private let logger = Logger(subsystem: "com.lookafter.app", category: "CaptureOfflineQueue")

    public private(set) var isOnline = true
    public var onConnectivityRestored: ((String) async -> Void)?

    private init() {
        if UserDefaults.standard.bool(forKey: Self.simulateOfflineKey) {
            isOnline = false
        }
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let wasOffline = !self.isOnline
                self.isOnline = path.status == .satisfied && !UserDefaults.standard.bool(forKey: Self.simulateOfflineKey)
                if wasOffline, self.isOnline {
                    let userIds = Set(self.pendingRecords().map(\.userId))
                    for userId in userIds {
                        await self.onConnectivityRestored?(userId)
                    }
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    private static let simulateOfflineKey = "uitest_simulate_offline"

    public var shouldDeferRouting: Bool { !isOnline }

    public func enqueue(_ request: CaptureRequest, userId: String) {
        var queue = loadAll()
        queue.append(
            PendingCapture(
                id: UUID().uuidString,
                request: request,
                userId: userId,
                queuedAt: Date()
            )
        )
        if queue.count > Self.maxPendingCaptures {
            let overflow = queue.count - Self.maxPendingCaptures
            queue.removeFirst(overflow)
            logger.warning("Offline capture queue capped; dropped \(overflow, privacy: .public) oldest item(s)")
        }
        persistence.save(queue, filename: filename)
    }

    public func pendingCount(for userId: String) -> Int {
        loadAll().filter { $0.userId == userId }.count
    }

    public func pendingRecords() -> [(request: CaptureRequest, userId: String)] {
        loadAll().map { ($0.request, $0.userId) }
    }

    /// Drain queued captures through the router; returns routed results.
    /// Failed or re-queued routes stay on disk until a later successful pass (BUG-006).
    public func processPending(
        userId: String,
        route: (CaptureRequest, String) async -> CaptureRouteResult
    ) async -> [CaptureRouteResult] {
        let records = loadAll().filter { $0.userId == userId }
        guard !records.isEmpty else { return [] }

        var results: [CaptureRouteResult] = []
        var remaining = loadAll()
        for record in records {
            let result = await route(record.request, record.userId)
            results.append(result)
            if Self.shouldRemoveFromQueue(after: result) {
                remaining.removeAll { $0.id == record.id }
            } else {
                logger.info("Keeping offline capture \(record.id, privacy: .public) after unsuccessful route")
            }
        }
        persistence.save(remaining, filename: filename)
        return results
    }

    public func clear() {
        persistence.save([PendingCapture](), filename: filename)
    }

    /// Terminal success or durable local inbox outcomes may drop the queue row.
    /// `queuedOffline` and unknown failures must retain the pending item.
    static func shouldRemoveFromQueue(after result: CaptureRouteResult) -> Bool {
        switch result.outcome {
        case .queuedOffline:
            return false
        case .taskCreated, .scheduledEvent, .journalEntry, .healthLog,
             .insightSaved, .archived, .needsReview:
            return true
        }
    }

    private func loadAll() -> [PendingCapture] {
        persistence.load([PendingCapture].self, filename: filename)
    }
}
