import Foundation

// MARK: - Retention Policy

/// Defines how long behavioral events are kept on device and when cleanup runs.
///
/// **Extension point:** Tune defaults per user tier or settings in a future milestone.
/// The store applies policy via `performRetentionCleanup(policy:)` — it does not auto-infer policy.
public struct BehaviorMemoryRetentionPolicy: Codable, Sendable, Equatable {
    /// Maximum age of events retained locally (days). Events older than this are eligible for removal.
    public var maxRetentionDays: Int
    /// Hard cap on append-only events stored in the active envelope.
    public var maxEventCount: Int
    /// When event count exceeds this threshold, archival/cleanup should run proactively.
    public var archivalThresholdCount: Int
    /// Maximum estimated storage size for the active envelope (bytes). Cleanup triggers when exceeded.
    public var maxStorageBytes: Int
    /// Whether automatic cleanup runs after each append when thresholds are exceeded.
    public var enableAutomaticCleanup: Bool

    public init(
        maxRetentionDays: Int = 90,
        maxEventCount: Int = 10_000,
        archivalThresholdCount: Int = 5_000,
        maxStorageBytes: Int = 5_242_880, // 5 MB
        enableAutomaticCleanup: Bool = false
    ) {
        self.maxRetentionDays = max(1, maxRetentionDays)
        self.maxEventCount = max(100, maxEventCount)
        self.archivalThresholdCount = max(100, archivalThresholdCount)
        self.maxStorageBytes = max(65_536, maxStorageBytes)
        self.enableAutomaticCleanup = enableAutomaticCleanup
    }

    /// Production defaults aligned with ATTENTION_OS_SPEC privacy posture (on-device, bounded).
    public static let `default` = BehaviorMemoryRetentionPolicy()
}

// MARK: - Archival Strategy

/// Long-term strategy for events evicted from the active envelope.
///
/// **Not fully implemented in D2.2+** — enum documents the migration path for large histories.
public enum BehaviorMemoryArchivalStrategy: String, Codable, Sendable, CaseIterable {
    /// No archival; trimmed events are discarded (current behavior).
    case discardOldest
    /// Future: move events older than retention window to a compressed archive file.
    case compressToArchive
    /// Future: export archive to user-controlled backup (Files app / iCloud).
    case exportToUserBackup
    /// Future: sync anonymized aggregates to CloudKit (opt-in only).
    case cloudKitOptIn
}

// MARK: - Schema Migration Plan

/// Documents supported and planned storage schema versions.
///
/// **v1 (current):** Flat JSON envelope with `events: [BehaviorMemoryStorageRecord]`.
///
/// **v2 (planned):** Split `activeEvents` + `archiveIndex` with compressed blob references;
/// migrate via `BehaviorMemoryStorageMigrator.migrateV1ToV2`.
///
/// **v3 (planned):** Per-user encryption envelope + chunked event segments for large histories.
public enum BehaviorMemorySchemaPlan {
    public static let currentVersion = 1
    public static let plannedVersions: [Int] = [2, 3]
}

// MARK: - Cleanup Report

/// Result of a retention cleanup pass initiated by the event store.
public struct BehaviorMemoryCleanupReport: Codable, Sendable, Equatable {
    public var removedEventCount: Int
    public var remainingEventCount: Int
    public var archivedEventCount: Int
    public var triggeredBy: BehaviorMemoryCleanupTrigger
    public var performedAt: Date

    public init(
        removedEventCount: Int = 0,
        remainingEventCount: Int = 0,
        archivedEventCount: Int = 0,
        triggeredBy: BehaviorMemoryCleanupTrigger = .manual,
        performedAt: Date = Date()
    ) {
        self.removedEventCount = max(removedEventCount, 0)
        self.remainingEventCount = max(remainingEventCount, 0)
        self.archivedEventCount = max(archivedEventCount, 0)
        self.triggeredBy = triggeredBy
        self.performedAt = performedAt
    }

    public static let noOp = BehaviorMemoryCleanupReport()
}

/// Why a cleanup pass ran.
public enum BehaviorMemoryCleanupTrigger: String, Codable, Sendable {
    case manual
    case eventCountThreshold
    case retentionDuration
    case storageSizeLimit
    case automatic
}

/// Hook invoked after cleanup for future archival backends (CloudKit, compressed archive).
public protocol BehaviorMemoryArchivalHandlerProtocol: Sendable {
    func archive(events: [BehaviorEvent], strategy: BehaviorMemoryArchivalStrategy) async throws -> Int
}

/// Default handler: discard-only until archival strategies are implemented.
public struct DiscardBehaviorMemoryArchivalHandler: BehaviorMemoryArchivalHandlerProtocol {
    public init() {}

    public func archive(events: [BehaviorEvent], strategy: BehaviorMemoryArchivalStrategy) async throws -> Int {
        // Future: branch on strategy. Currently all strategies discard during cleanup.
        events.count
    }
}
