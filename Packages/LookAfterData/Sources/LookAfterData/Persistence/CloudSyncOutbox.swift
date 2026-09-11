import Foundation
import Network
import FirebaseFirestore
import LookAfterCore

/// Durable pending Firestore writes for any user collection (generic SyncOutbox).
@MainActor
public final class CloudSyncOutbox {
    public static let shared = CloudSyncOutbox()

    public enum Operation: String, Codable, Sendable {
        case upsert
        case upsertMerge
        case delete
    }

    public struct Entry: Codable, Identifiable, Sendable {
        public var id: String
        public var collection: String
        public var documentId: String
        public var userId: String
        public var operation: Operation
        public var payloadJSON: Data?
        public var queuedAt: Date
    }

    private let filename = "cloud_sync_outbox"
    private let legacyTaskFilename = "task_sync_outbox"
    private let persistence = LocalPersistenceManager.shared
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.lookafter.cloud-sync.connectivity")
    private var isOnline = true
    private var isDraining = false
    private var didMigrateLegacy = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let wasOffline = !self.isOnline
                self.isOnline = path.status == .satisfied
                if wasOffline, self.isOnline {
                    await self.drain()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    public func enqueue(
        collection: String,
        documentId: String,
        userId: String,
        operation: Operation,
        payloadJSON: Data?
    ) {
        migrateLegacyIfNeeded()
        // Coalesce: one pending op per document. Delete replaces any prior upsert.
        var queue = loadAll().filter { !($0.collection == collection && $0.documentId == documentId) }
        queue.append(
            Entry(
                id: UUID().uuidString,
                collection: collection,
                documentId: documentId,
                userId: userId,
                operation: operation,
                payloadJSON: payloadJSON,
                queuedAt: Date()
            )
        )
        persistence.save(queue, filename: filename)
        Task { await drain() }
    }

    public func enqueueCodable<T: Encodable>(
        _ value: T,
        collection: String,
        documentId: String,
        userId: String,
        merge: Bool
    ) {
        guard let data = try? encode(value) else { return }
        enqueue(
            collection: collection,
            documentId: documentId,
            userId: userId,
            operation: merge ? .upsertMerge : .upsert,
            payloadJSON: data
        )
    }

    public var pendingCount: Int {
        migrateLegacyIfNeeded()
        return loadAll().count
    }

    @discardableResult
    public func drain(firebase: FirebaseManager = .shared) async -> Int {
        migrateLegacyIfNeeded()
        guard !isDraining else { return 0 }
        isDraining = true
        defer { isDraining = false }

        guard firebase.isCloudSyncAvailable else { return 0 }

        var completed = 0
        var stillPending: [Entry] = []

        for entry in loadAll() {
            guard let ref = firebase.userCollection(entry.collection) else {
                stillPending.append(entry)
                continue
            }
            do {
                switch entry.operation {
                case .delete:
                    try await ref.document(entry.documentId).delete()
                case .upsert, .upsertMerge:
                    guard let payload = entry.payloadJSON,
                          let dict = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
                        stillPending.append(entry)
                        continue
                    }
                    try await ref.document(entry.documentId).setData(dict, merge: entry.operation == .upsertMerge)
                }
                completed += 1
            } catch {
                stillPending.append(entry)
            }
        }

        persistence.save(stillPending, filename: filename)
        return completed
    }

    public func clearAll() {
        persistence.save([Entry](), filename: filename)
        persistence.save([LegacyTaskEntry](), filename: legacyTaskFilename)
    }

    #if DEBUG
    public func resetForTests() {
        clearAll()
        didMigrateLegacy = true
    }
    #endif

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(value)
    }

    private func loadAll() -> [Entry] {
        persistence.load([Entry].self, filename: filename)
    }

    private func migrateLegacyIfNeeded() {
        guard !didMigrateLegacy else { return }
        didMigrateLegacy = true
        let legacy = persistence.load([LegacyTaskEntry].self, filename: legacyTaskFilename)
        guard !legacy.isEmpty else { return }
        var queue = loadAll()
        for entry in legacy {
            queue.append(
                Entry(
                    id: entry.id,
                    collection: "tasks",
                    documentId: entry.taskId,
                    userId: entry.userId,
                    operation: Operation(rawValue: entry.operation.rawValue) ?? .upsert,
                    payloadJSON: entry.payloadJSON,
                    queuedAt: entry.queuedAt
                )
            )
        }
        persistence.save(queue, filename: filename)
        persistence.save([LegacyTaskEntry](), filename: legacyTaskFilename)
    }

    private struct LegacyTaskEntry: Codable {
        var id: String
        var taskId: String
        var userId: String
        var operation: CloudSyncOutbox.Operation
        var payloadJSON: Data?
        var queuedAt: Date
    }
}
