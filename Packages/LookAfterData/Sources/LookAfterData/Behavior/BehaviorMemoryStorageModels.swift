import Foundation
import LookAfterCore

// MARK: - Schema Version

/// Supported Behavior Memory storage schema versions.
/// Increment when `BehaviorMemoryStorageRecord` shape changes and add a migrator step.
public enum BehaviorMemorySchemaVersion: Int, Codable, Sendable, CaseIterable {
    /// Initial schema: append-only `events` array with metadata envelope.
    case v1 = 1
}

// MARK: - Storage Record (Persistence Layer)

/// On-disk representation of a single behavioral event.
/// Mirrors `BehaviorEvent` but is owned by the persistence layer so storage can evolve
/// independently of domain types (e.g. field renames, compression, denormalization).
struct BehaviorMemoryStorageRecord: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var kind: BehaviorEventKind
    var taskID: String?
    var taskTitle: String?
    var lifeAreaRawValue: String?
    var recordedAt: Date
    var durationMinutes: Int?
    var context: BehaviorContextMetadata

    init(from event: BehaviorEvent) {
        id = event.id
        kind = event.kind
        taskID = event.taskID
        taskTitle = event.taskTitle
        lifeAreaRawValue = event.lifeAreaRawValue
        recordedAt = event.recordedAt
        durationMinutes = event.durationMinutes
        context = event.context
    }

    func toDomainEvent() -> BehaviorEvent {
        BehaviorEvent(
            id: id,
            kind: kind,
            taskID: taskID,
            taskTitle: taskTitle,
            lifeAreaRawValue: lifeAreaRawValue,
            recordedAt: recordedAt,
            durationMinutes: durationMinutes,
            context: context
        )
    }
}

// MARK: - Storage Envelope

/// Versioned top-level document written atomically to disk.
struct BehaviorMemoryStorageEnvelope: Codable, Sendable, Equatable {
    var schemaVersion: Int
    var createdAt: Date
    var updatedAt: Date
    var events: [BehaviorMemoryStorageRecord]

    static func empty(now: Date = Date()) -> BehaviorMemoryStorageEnvelope {
        BehaviorMemoryStorageEnvelope(
            schemaVersion: BehaviorMemorySchemaVersion.v1.rawValue,
            createdAt: now,
            updatedAt: now,
            events: []
        )
    }
}

// MARK: - Codec

/// Encodes/decodes storage envelopes with consistent date strategy.
enum BehaviorMemoryStorageCodec {
    /// Dedicated encoder keeps sortedKeys for stable vault hashing (PERF-018).
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static func encode(_ envelope: BehaviorMemoryStorageEnvelope) throws -> Data {
        try encoder.encode(envelope)
    }

    static func decode(_ data: Data) throws -> BehaviorMemoryStorageEnvelope {
        try SharedFormatters.jsonDecoderSeconds.decode(BehaviorMemoryStorageEnvelope.self, from: data)
    }
}
