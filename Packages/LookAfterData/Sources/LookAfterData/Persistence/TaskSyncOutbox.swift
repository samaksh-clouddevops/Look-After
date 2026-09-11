import Foundation
import LookAfterCore

/// Durable pending Firestore task writes. Thin facade over `CloudSyncOutbox`.
@MainActor
public final class TaskSyncOutbox {
    public static let shared = TaskSyncOutbox()

    public typealias Operation = CloudSyncOutbox.Operation

    private init() {}

    public func enqueueUpsert(_ task: LifeTask, merge: Bool) {
        CloudSyncOutbox.shared.enqueueCodable(
            task,
            collection: "tasks",
            documentId: task.id,
            userId: task.userId,
            merge: merge
        )
    }

    public func enqueueDelete(taskId: String, userId: String) {
        CloudSyncOutbox.shared.enqueue(
            collection: "tasks",
            documentId: taskId,
            userId: userId,
            operation: .delete,
            payloadJSON: nil
        )
    }

    public var pendingCount: Int { CloudSyncOutbox.shared.pendingCount }

    @discardableResult
    public func drain(firebase: FirebaseManager = .shared) async -> Int {
        await CloudSyncOutbox.shared.drain(firebase: firebase)
    }

    public func clearAll() {
        CloudSyncOutbox.shared.clearAll()
    }

    #if DEBUG
    public func resetForTests() {
        CloudSyncOutbox.shared.resetForTests()
    }
    #endif
}
