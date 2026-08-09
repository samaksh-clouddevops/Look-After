import Foundation

/// Cloud mutation queued until successfully applied (Phase 2 WP 2.1 / ADR-006).
public enum SyncOutboxEntityType: String, Codable, Sendable, CaseIterable {
    case task
    case inboxItem
    case healthSummary
    case bill
    case shoppingItem
    case relationship
    case journalEntry
}

public enum SyncOutboxOperation: String, Codable, Sendable, CaseIterable {
    case upsert
    case delete
}

public enum SyncOutboxStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case inFlight
    case failed
    case dead
}

public struct SyncOutboxRecord: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var userId: String
    public var entityType: SyncOutboxEntityType
    public var entityId: String
    public var operation: SyncOutboxOperation
    /// JSON object payload for upsert; empty for delete.
    public var payloadJSON: Data
    public var attempts: Int
    public var status: SyncOutboxStatus
    public var nextAttemptAt: Date
    public var lastError: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        userId: String,
        entityType: SyncOutboxEntityType,
        entityId: String,
        operation: SyncOutboxOperation,
        payloadJSON: Data = Data(),
        attempts: Int = 0,
        status: SyncOutboxStatus = .pending,
        nextAttemptAt: Date = Date(),
        lastError: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.entityType = entityType
        self.entityId = entityId
        self.operation = operation
        self.payloadJSON = payloadJSON
        self.attempts = attempts
        self.status = status
        self.nextAttemptAt = nextAttemptAt
        self.lastError = lastError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
