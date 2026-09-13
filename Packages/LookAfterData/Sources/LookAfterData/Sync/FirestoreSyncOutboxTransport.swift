import Foundation
import LookAfterCore

/// Applies outbox records to Firestore via FirebaseManager.
@MainActor
public struct FirestoreSyncOutboxTransport: SyncOutboxTransporting {

    public init() {}

    public func apply(_ record: SyncOutboxRecord) async throws {
        let firebase = FirebaseManager.shared
        guard firebase.isCloudSyncAvailable else {
            throw TransportError.cloudUnavailable
        }

        let collection: String
        switch record.entityType {
        case .task: collection = "tasks"
        case .inboxItem: collection = "inbox_items"
        case .healthSummary: collection = "health_summaries"
        case .bill: collection = "bills"
        case .shoppingItem: collection = "shopping_items"
        case .relationship: collection = "relationships"
        case .journalEntry: collection = "journal_entries"
        }

        guard let ref = firebase.userCollection(collection) else {
            throw TransportError.cloudUnavailable
        }

        switch record.operation {
        case .delete:
            try await ref.document(record.entityId).delete()
        case .upsert:
            guard !record.payloadJSON.isEmpty else {
                throw TransportError.emptyPayload
            }
            guard let dict = try JSONSerialization.jsonObject(with: record.payloadJSON) as? [String: Any] else {
                throw TransportError.invalidPayload
            }
            try await ref.document(record.entityId).setData(dict, merge: true)
        }
    }

    public enum TransportError: Error, LocalizedError {
        case cloudUnavailable
        case emptyPayload
        case invalidPayload

        public var errorDescription: String? {
            switch self {
            case .cloudUnavailable: return "Cloud sync unavailable"
            case .emptyPayload: return "Empty outbox payload"
            case .invalidPayload: return "Invalid outbox JSON"
            }
        }
    }
}
