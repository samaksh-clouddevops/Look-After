import XCTest
@testable import LookAfterData
import LookAfterCore

final class BehaviorMemoryStoreTests: XCTestCase {

    private var tempDirectory: URL!
    private var backend: FileBehaviorMemoryPersistenceBackend!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BehaviorMemoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        backend = FileBehaviorMemoryPersistenceBackend(directoryURL: tempDirectory)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeStore() async -> BehaviorMemoryStore {
        await BehaviorMemoryStore(backend: backend)
    }

    private func sampleTask(id: String = UUID().uuidString, title: String = "API Review") -> LifeTask {
        LifeTask(id: id, title: title, lifeArea: .work, status: .inProgress, estimatedMinutes: 18)
    }

    private func sampleContext(energy: Double = 0.72) -> EnvironmentContext {
        EnvironmentContext(
            energyScore: energy,
            hrvDelta: 0.05,
            sleepQuality: .good,
            weather: .clear,
            timeOfDay: .morning,
            isWeekend: false
        )
    }

    /// Aggregation via `BehaviorMemorySnapshotBuilder` — not the store's responsibility.
    private func aggregatedSnapshot(from store: BehaviorMemoryStore) async -> BehaviorMemorySnapshot {
        BehaviorMemorySnapshotBuilder.build(from: await store.fetchEvents())
    }

    // MARK: - Empty Store

    func testEmptyStoreSnapshot() async {
        let store = await makeStore()
        let snapshot = await aggregatedSnapshot(from: store)

        XCTAssertEqual(snapshot.recordedEventCount, 0)
        XCTAssertEqual(snapshot.completionEventCount, 0)
        XCTAssertEqual(snapshot.deferralEventCount, 0)
        XCTAssertEqual(snapshot.flowSessionEventCount, 0)
        XCTAssertTrue(snapshot.deferralRecords.isEmpty)
        XCTAssertTrue(snapshot.patterns.isEmpty)
        XCTAssertNil(snapshot.preferredFlowDurationMinutes)
    }

    func testEmptyStoreLoadReport() async {
        let store = await makeStore()
        let report = await store.loadReport
        XCTAssertTrue(report.wasCreatedEmpty)
        XCTAssertFalse(report.wasRecoveredFromCorruption)
    }

    // MARK: - Record Completion

    func testRecordCompletion() async {
        let store = await makeStore()
        let task = sampleTask()

        await store.recordCompletion(task: task, durationMinutes: 18, context: sampleContext())
        let snapshot = await aggregatedSnapshot(from: store)

        XCTAssertEqual(snapshot.recordedEventCount, 1)
        XCTAssertEqual(snapshot.completionEventCount, 1)
        XCTAssertEqual(snapshot.deferralEventCount, 0)

        let events = await store.fetchEvents()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].kind, .taskCompletion)
        XCTAssertEqual(events[0].taskID, task.id)
        XCTAssertEqual(events[0].durationMinutes, 18)
        XCTAssertEqual(events[0].context.energyScore, 0.72, accuracy: 0.001)
        XCTAssertEqual(events[0].lifeAreaRawValue, LifeArea.work.rawValue)
    }

    // MARK: - Record Deferral

    func testRecordDeferralAggregatesInSnapshot() async {
        let store = await makeStore()
        let task = sampleTask()

        await store.recordDeferral(task: task, context: sampleContext())
        await store.recordDeferral(task: task, context: sampleContext())
        let snapshot = await aggregatedSnapshot(from: store)

        XCTAssertEqual(snapshot.deferralEventCount, 2)
        XCTAssertEqual(snapshot.deferralRecords.count, 1)
        XCTAssertEqual(snapshot.deferralCount(for: task.id), 2)
        XCTAssertNotNil(snapshot.deferralRecords.first?.lastDeferredAt)
    }

    func testRecordDeferralWithoutContextUsesBaseline() async {
        let store = await makeStore()
        let task = sampleTask()

        await store.recordDeferral(task: task, context: nil)
        let events = await store.fetchEvents()

        XCTAssertEqual(events[0].kind, .taskDeferral)
        XCTAssertNotNil(events[0].context.timeOfDay)
    }

    // MARK: - Flow Session

    func testRecordFlowSession() async {
        let store = await makeStore()
        let task = sampleTask()

        await store.recordFlowSession(task: task, durationMinutes: 25, context: sampleContext())
        let snapshot = await aggregatedSnapshot(from: store)

        XCTAssertEqual(snapshot.flowSessionEventCount, 1)
        let events = await store.fetchEvents()
        XCTAssertEqual(events[0].kind, .flowSessionEnded)
        XCTAssertEqual(events[0].durationMinutes, 25)
    }

    // MARK: - Persistence Across Reload

    func testPersistenceAcrossReload() async {
        let task = sampleTask(title: "Persist Me")
        let store1 = await makeStore()
        await store1.recordCompletion(task: task, durationMinutes: 10, context: sampleContext())

        let store2 = await BehaviorMemoryStore(backend: backend)
        let snapshot = await aggregatedSnapshot(from: store2)

        XCTAssertEqual(snapshot.recordedEventCount, 1)
        XCTAssertEqual(snapshot.completionEventCount, 1)
        let events = await store2.fetchEvents()
        XCTAssertEqual(events.first?.taskTitle, "Persist Me")
    }

    // MARK: - Corrupted Storage Recovery

    func testCorruptedStorageRecovery() async throws {
        let corruptURL = tempDirectory.appendingPathComponent(FileBehaviorMemoryPersistenceBackend.defaultFileName)
        try Data("{ not valid json".utf8).write(to: corruptURL)

        let store = await makeStore()
        let report = await store.loadReport

        XCTAssertTrue(report.wasRecoveredFromCorruption)
        XCTAssertNotNil(report.quarantinedFileName)

        let quarantineDir = tempDirectory.appendingPathComponent("Quarantine")
        let quarantineFiles = try FileManager.default.contentsOfDirectory(at: quarantineDir, includingPropertiesForKeys: nil)
        XCTAssertFalse(quarantineFiles.isEmpty)

        let snapshot = await aggregatedSnapshot(from: store)
        XCTAssertEqual(snapshot.recordedEventCount, 0)

        await store.recordCompletion(task: sampleTask(), durationMinutes: 5, context: sampleContext())
        let countAfterRecovery = await store.eventCount()
        XCTAssertEqual(countAfterRecovery, 1)
    }

    // MARK: - Concurrent Writes

    func testConcurrentWrites() async {
        let store = await makeStore()
        let context = sampleContext()

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<100 {
                group.addTask {
                    let task = LifeTask(title: "Task \(index)", lifeArea: .work)
                    await store.recordCompletion(task: task, durationMinutes: 5, context: context)
                }
            }
        }

        let count = await store.eventCount()
        XCTAssertEqual(count, 100)

        let snapshot = await aggregatedSnapshot(from: store)
        XCTAssertEqual(snapshot.completionEventCount, 100)
    }

    // MARK: - In-Memory Backend

    func testInMemoryBackendIsolation() async {
        let memoryBackend = InMemoryBehaviorMemoryPersistenceBackend()
        let store = await BehaviorMemoryStore(backend: memoryBackend)
        await store.recordDeferral(task: sampleTask(), context: sampleContext())

        let snapshot = await aggregatedSnapshot(from: store)
        XCTAssertEqual(snapshot.deferralEventCount, 1)
    }

    // MARK: - Performance

    func testPerformanceWithLargeDataset() async {
        let store = await makeStore()
        let context = sampleContext()

        let start = Date()
        for index in 0..<2_000 {
            let task = LifeTask(title: "Perf \(index)")
            await store.recordCompletion(task: task, durationMinutes: 5, context: context)
        }
        let elapsed = Date().timeIntervalSince(start)

        let snapshot = await aggregatedSnapshot(from: store)
        XCTAssertEqual(snapshot.recordedEventCount, 2_000)
        XCTAssertLessThan(elapsed, 30, "Recording 2,000 events should complete within 30s (took \(elapsed)s)")
    }

    func testSnapshotPerformanceWithLargeDataset() async {
        let memoryBackend = InMemoryBehaviorMemoryPersistenceBackend()
        let store = await BehaviorMemoryStore(backend: memoryBackend)
        let context = sampleContext()

        for index in 0..<5_000 {
            let task = LifeTask(title: "Snapshot Perf \(index)")
            await store.recordCompletion(task: task, durationMinutes: 5, context: context)
        }

        let start = Date()
        _ = BehaviorMemorySnapshotBuilder.build(from: await store.fetchEvents())
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 1.0, "Snapshot over 5,000 events should be under 1s (took \(elapsed)s)")
    }

    // MARK: - Schema & Codec

    func testStorageEnvelopeRoundTrip() throws {
        let event = BehaviorEventFactory.completion(
            task: LifeTask(title: "Codec Test"),
            durationMinutes: 15,
            context: EnvironmentContext.baseline
        )
        var envelope = BehaviorMemoryStorageEnvelope.empty()
        envelope.events = [BehaviorMemoryStorageRecord(from: event)]

        let data = try BehaviorMemoryStorageCodec.encode(envelope)
        let decoded = try BehaviorMemoryStorageCodec.decode(data)

        XCTAssertEqual(decoded.schemaVersion, BehaviorMemorySchemaVersion.v1.rawValue)
        XCTAssertEqual(decoded.events.count, 1)
        XCTAssertEqual(decoded.events[0].taskTitle, "Codec Test")
    }

    func testMigratorMigratedFromOlderVersion() throws {
        var legacy = BehaviorMemoryStorageEnvelope.empty()
        legacy.schemaVersion = 0

        let data = try BehaviorMemoryStorageCodec.encode(legacy)
        let result = BehaviorMemoryStorageMigrator.load(data: data)
        XCTAssertEqual(result.envelope.schemaVersion, BehaviorMemorySchemaVersion.v1.rawValue)
        XCTAssertEqual(result.report.migratedFromVersion, 0)
    }

    // MARK: - Context Metadata

    func testContextMetadataCapturesTimeOfDayAndEnergy() async {
        let store = await makeStore()
        var context = sampleContext(energy: 0.88)
        context.timeOfDay = .afternoon

        await store.recordFlowSession(task: sampleTask(), durationMinutes: 45, context: context)
        let event = await store.fetchEvents().first!

        XCTAssertEqual(event.context.flowPersonality, FlowPersonality.peak)
        XCTAssertEqual(event.context.timeOfDay, .afternoon)
        XCTAssertEqual(event.context.energyScore, 0.88, accuracy: 0.001)
    }

    // MARK: - Retention Cleanup

    func testRetentionCleanupRemovesOldEvents() async {
        let store = await makeStore()

        await store.recordCompletion(
            task: LifeTask(title: "Old"),
            durationMinutes: 5,
            context: sampleContext()
        )

        // Manually inject old event via fetch + we can't easily backdate without internal access
        // Record 3 more recent events
        for i in 0..<3 {
            await store.recordCompletion(
                task: LifeTask(title: "Recent \(i)"),
                durationMinutes: 5,
                context: sampleContext()
            )
        }

        var policy = BehaviorMemoryRetentionPolicy.default
        policy.maxEventCount = 2

        let report = await store.performRetentionCleanup(policy: policy)
        XCTAssertEqual(report.remainingEventCount, 2)
        XCTAssertEqual(report.removedEventCount, 2)
    }

    func testStoreDoesNotIncludePatternsInRawEvents() async {
        let store = await makeStore()
        await store.recordCompletion(task: sampleTask(), durationMinutes: 10, context: sampleContext())
        let events = await store.fetchEvents()
        XCTAssertEqual(events.count, 1)
        // Patterns only appear via analysis engine, not in raw events
        let snapshot = await DefaultBehaviorAnalysisEngine().buildSnapshot(from: events)
        XCTAssertTrue(snapshot.patterns.isEmpty)
    }
}
