import Foundation
import LifeOSCore

/// Thread-safe append-only behavioral event store.
///
/// ## Responsibility boundary
/// This actor **only** appends, loads, persists, and optionally trims raw events.
/// It must never perform analytics, pattern detection, or inference.
/// Consumption pipeline:
/// `fetchEvents()` → `BehaviorAnalysisEngineProtocol.buildSnapshot(from:)` → Flow Director.
///
/// ## Retention
/// Call `performRetentionCleanup(policy:strategy:archivalHandler:)` manually or when
/// `policy.enableAutomaticCleanup` is wired by the app layer after append.
public actor BehaviorMemoryStore: BehaviorMemoryStoreProtocol {

    private let backend: BehaviorMemoryPersistenceBackendProtocol
    private var envelope: BehaviorMemoryStorageEnvelope

    public private(set) var loadReport: BehaviorMemoryLoadReport

    public init(backend: BehaviorMemoryPersistenceBackendProtocol) async {
        self.backend = backend
        let data = try? await backend.loadData()

        let fileBackend = backend as? FileBehaviorMemoryPersistenceBackend
        let loaded = BehaviorMemoryStorageMigrator.load(data: data) { corruptData, name in
            fileBackend?.quarantineCorruptData(corruptData, fileName: name)
        }

        loadReport = loaded.report
        envelope = loaded.envelope
    }

    // MARK: - Recording

    public func recordCompletion(
        task: LifeTask,
        durationMinutes: Int,
        context: EnvironmentContext
    ) async {
        await append(BehaviorEventFactory.completion(
            task: task,
            durationMinutes: durationMinutes,
            context: context
        ))
    }

    public func recordDeferral(task: LifeTask, context: EnvironmentContext?) async {
        await append(BehaviorEventFactory.deferral(task: task, context: context))
    }

    public func recordFlowSession(
        task: LifeTask?,
        durationMinutes: Int,
        context: EnvironmentContext
    ) async {
        await append(BehaviorEventFactory.flowSessionEnded(
            task: task,
            durationMinutes: durationMinutes,
            context: context
        ))
    }

    // MARK: - Read (Raw Events Only)

    public func fetchEvents() async -> [BehaviorEvent] {
        envelope.events.map { $0.toDomainEvent() }
    }

    public func eventCount() async -> Int {
        envelope.events.count
    }

    /// Alias retained for tests and migration from D2.2 naming.
    public func allEvents() async -> [BehaviorEvent] {
        await fetchEvents()
    }

    // MARK: - Retention & Cleanup

    public func performRetentionCleanup(
        policy: BehaviorMemoryRetentionPolicy = .default,
        strategy: BehaviorMemoryArchivalStrategy = .discardOldest,
        archivalHandler: BehaviorMemoryArchivalHandlerProtocol = DiscardBehaviorMemoryArchivalHandler()
    ) async -> BehaviorMemoryCleanupReport {
        let now = Date()
        let cutoff = Calendar.current.date(byAdding: .day, value: -policy.maxRetentionDays, to: now) ?? now

        var removed: [BehaviorEvent] = []
        var kept: [BehaviorMemoryStorageRecord] = []

        for record in envelope.events {
            if record.recordedAt < cutoff {
                removed.append(record.toDomainEvent())
            } else {
                kept.append(record)
            }
        }

        var trigger: BehaviorMemoryCleanupTrigger = .retentionDuration

        if kept.count > policy.maxEventCount {
            let overflow = kept.count - policy.maxEventCount
            let sorted = kept.sorted { $0.recordedAt < $1.recordedAt }
            removed.append(contentsOf: sorted.prefix(overflow).map { $0.toDomainEvent() })
            kept = Array(sorted.suffix(policy.maxEventCount))
            trigger = .eventCountThreshold
        }

        if let data = try? BehaviorMemoryStorageCodec.encode(
            BehaviorMemoryStorageEnvelope(
                schemaVersion: envelope.schemaVersion,
                createdAt: envelope.createdAt,
                updatedAt: now,
                events: kept
            )
        ), data.count > policy.maxStorageBytes, kept.count > 100 {
            let target = max(kept.count / 2, 100)
            let overflow = kept.count - target
            let sorted = kept.sorted { $0.recordedAt < $1.recordedAt }
            removed.append(contentsOf: sorted.prefix(overflow).map { $0.toDomainEvent() })
            kept = Array(sorted.suffix(target))
            trigger = .storageSizeLimit
        }

        var archivedCount = 0
        if !removed.isEmpty {
            archivedCount = (try? await archivalHandler.archive(events: removed, strategy: strategy)) ?? 0
        }

        envelope.events = kept
        envelope.updatedAt = now
        await persist()

        return BehaviorMemoryCleanupReport(
            removedEventCount: removed.count,
            remainingEventCount: kept.count,
            archivedEventCount: archivedCount,
            triggeredBy: removed.isEmpty ? .manual : trigger,
            performedAt: now
        )
    }

    // MARK: - Private

    private func append(_ event: BehaviorEvent) async {
        envelope.events.append(BehaviorMemoryStorageRecord(from: event))
        envelope.updatedAt = Date()
        await persist()
    }

    private func persist() async {
        do {
            let data = try BehaviorMemoryStorageCodec.encode(envelope)
            try await backend.saveData(data)
        } catch {
            #if DEBUG
            print("[BehaviorMemoryStore] Persist failed: \(error.localizedDescription)")
            #endif
        }
    }
}
