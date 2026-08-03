import Foundation
import LookAfterCore

/// Outcome metadata from loading a storage document (for diagnostics and tests).
public struct BehaviorMemoryLoadReport: Sendable, Equatable {
    public var wasCreatedEmpty: Bool
    public var wasRecoveredFromCorruption: Bool
    public var quarantinedFileName: String?
    public var migratedFromVersion: Int?
    public var loadedEventCount: Int

    public init(
        wasCreatedEmpty: Bool = false,
        wasRecoveredFromCorruption: Bool = false,
        quarantinedFileName: String? = nil,
        migratedFromVersion: Int? = nil,
        loadedEventCount: Int = 0
    ) {
        self.wasCreatedEmpty = wasCreatedEmpty
        self.wasRecoveredFromCorruption = wasRecoveredFromCorruption
        self.quarantinedFileName = quarantinedFileName
        self.migratedFromVersion = migratedFromVersion
        self.loadedEventCount = loadedEventCount
    }
}

/// Migrates Behavior Memory storage documents between schema versions.
///
/// **Extension point:** add `migrateV1ToV2(_:)` when schema v2 ships and register it in `migrateToCurrent`.
enum BehaviorMemoryStorageMigrator {

    static let currentSchemaVersion = BehaviorMemorySchemaVersion.v1.rawValue

    /// Loads bytes, migrates to current schema, quarantines corrupt data, or returns an empty envelope.
    static func load(
        data: Data?,
        quarantineHandler: ((Data, String) -> Void)? = nil
    ) -> (envelope: BehaviorMemoryStorageEnvelope, report: BehaviorMemoryLoadReport) {
        guard let data, !data.isEmpty else {
            return (.empty(), BehaviorMemoryLoadReport(wasCreatedEmpty: true))
        }

        do {
            let decoded = try BehaviorMemoryStorageCodec.decode(data)
            let originalVersion = decoded.schemaVersion
            let migrated = migrateToCurrent(decoded)
            return (
                migrated,
                BehaviorMemoryLoadReport(
                    migratedFromVersion: originalVersion != migrated.schemaVersion ? originalVersion : nil,
                    loadedEventCount: migrated.events.count
                )
            )
        } catch {
            let quarantineName = "behavior_memory_corrupt_\(Int(Date().timeIntervalSince1970)).json"
            quarantineHandler?(data, quarantineName)
            return (
                .empty(),
                BehaviorMemoryLoadReport(
                    wasRecoveredFromCorruption: true,
                    quarantinedFileName: quarantineName
                )
            )
        }
    }

    /// Applies sequential migrations until `currentSchemaVersion` is reached.
    static func migrateToCurrent(_ envelope: BehaviorMemoryStorageEnvelope) -> BehaviorMemoryStorageEnvelope {
        var working = envelope

        // Future: if working.schemaVersion == 1 { working = migrateV1ToV2(working) }

        if working.schemaVersion < currentSchemaVersion {
            working.schemaVersion = currentSchemaVersion
        }

        return working
    }
}
