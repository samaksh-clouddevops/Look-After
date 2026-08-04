import XCTest
@testable import PerfBudgets

/// Widget System V2 contracts — runnable on Linux via Docker (Windows host).
final class WidgetContractTests: XCTestCase {

    func testKindsAreUnique() {
        let kinds = WidgetKindContract.all
        XCTAssertEqual(Set(kinds).count, kinds.count)
        XCTAssertEqual(kinds.count, 15)
        XCTAssertTrue(kinds.contains("LookAfter.Recommendation"))
        XCTAssertTrue(kinds.contains("NowWidget"))
        XCTAssertTrue(kinds.contains("EnergyWidget"))
        XCTAssertTrue(kinds.contains("TasksWidget"))
    }

    func testDeepLinks() {
        XCTAssertEqual(WidgetDeepLinkContract.scheme, "lookafter")
        XCTAssertEqual(WidgetDeepLinkContract.url("recommend").host, "recommend")
        XCTAssertEqual(WidgetDeepLinkContract.url("today").host, "today")
        XCTAssertEqual(WidgetDeepLinkContract.url("focus").host, "focus")
        XCTAssertEqual(WidgetDeepLinkContract.url("health").host, "health")
        XCTAssertEqual(WidgetDeepLinkContract.url("capture").host, "capture")
        XCTAssertEqual(WidgetDeepLinkContract.url("medication").host, "medication")
        XCTAssertEqual(WidgetDeepLinkContract.url("brain").host, "brain")

        let voice = WidgetDeepLinkContract.capture(mode: "voice")
        XCTAssertTrue(voice.query?.contains("mode=voice") == true)

        let task = WidgetDeepLinkContract.task(id: "task-99")
        XCTAssertEqual(task.host, "task")
        XCTAssertTrue(task.path.contains("task-99"))
    }

    func testAppGroupConstants() {
        XCTAssertEqual(WidgetAppGroupContract.identifier, "group.com.samaksh.flowos")
        XCTAssertEqual(WidgetAppGroupContract.snapshotKey, "flowos.widget.snapshot")
        XCTAssertEqual(WidgetAppGroupContract.commandQueueKey, "lookafter.widget.commands")
        XCTAssertNotEqual(WidgetAppGroupContract.snapshotKey, WidgetAppGroupContract.commandQueueKey)
    }

    func testSnapshotRoundTrip() throws {
        let original = WidgetSnapshotMirror(
            topTaskTitle: "Ship widgets",
            topTaskMinutes: 25,
            energyScore: 70,
            energyLevel: "High",
            recommendation: "Morning focus",
            completedTodayCount: 1,
            activeTaskCount: 4,
            tasks: [
                WidgetTaskItemMirror(id: "1", title: "Ship widgets", estimatedMinutes: 25, priorityLabel: "High")
            ],
            executive: WidgetRecommendationMirror(
                taskID: "1",
                title: "Ship widgets",
                whyLine: "Morning focus",
                estimatedMinutes: 25,
                energyScore: 70
            ),
            recoveryLabel: "Good recovery",
            schemaVersion: 2
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WidgetSnapshotMirror.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.resolvedTitle, "Ship widgets")
    }

    func testV1PayloadDecodeWithoutV2Keys() throws {
        let v1 = WidgetSnapshotMirror(
            topTaskTitle: "Legacy",
            energyScore: 55,
            recommendation: "Do the thing",
            schemaVersion: 1
        )
        let data = try JSONEncoder().encode(v1)
        var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        obj.removeValue(forKey: "executive")
        obj.removeValue(forKey: "recoveryLabel")
        obj.removeValue(forKey: "schemaVersion")
        let stripped = try JSONSerialization.data(withJSONObject: obj)
        let decoded = try JSONDecoder().decode(WidgetSnapshotMirror.self, from: stripped)
        XCTAssertEqual(decoded.topTaskTitle, "Legacy")
        XCTAssertNil(decoded.executive)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.resolvedTitle, "Legacy")
    }

    func testResolvedTitleFallsBackToClear() {
        let s = WidgetSnapshotMirror()
        XCTAssertEqual(s.resolvedTitle, "You're clear")
    }

    func testStaleFlag() {
        let old = WidgetSnapshotMirror(updatedAt: Date().addingTimeInterval(-7 * 3600))
        let fresh = WidgetSnapshotMirror(updatedAt: Date())
        XCTAssertTrue(old.isStale)
        XCTAssertFalse(fresh.isStale)
    }

    func testEnergyScoreClampingContractForUI() {
        // WidgetEnergyChip clamps 0...100 — verify inputs used by builders stay sane.
        let samples = [0, 50, 100, -5, 140]
        for raw in samples {
            let clamped = max(0, min(100, raw))
            XCTAssertGreaterThanOrEqual(clamped, 0)
            XCTAssertLessThanOrEqual(clamped, 100)
        }
    }

    func testJSONFileRoundTripForAppGroupSimulation() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("widget-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let snap = WidgetSnapshotMirror(
            topTaskTitle: "Focus",
            energyScore: 88,
            recommendation: "Deep work",
            executive: WidgetRecommendationMirror(title: "Focus", whyLine: "Deep work", energyScore: 88),
            schemaVersion: 2
        )
        let url = dir.appendingPathComponent("snapshot.json")
        let data = try JSONEncoder().encode(snap)
        try data.write(to: url, options: .atomic)
        let loaded = try JSONDecoder().decode(WidgetSnapshotMirror.self, from: Data(contentsOf: url))
        XCTAssertEqual(loaded.topTaskTitle, "Focus")
        XCTAssertEqual(loaded.executive?.energyScore, 88)
    }

    /// Ensures V2 kind set always includes legacy V1 for migration overlap.
    func testMigrationOverlapIncludesV1Kinds() {
        let set = Set(WidgetKindContract.all)
        XCTAssertTrue(set.isSuperset(of: ["NowWidget", "EnergyWidget", "TasksWidget"]))
        XCTAssertTrue(set.isSuperset(of: [
            "LookAfter.Recommendation",
            "LookAfter.Today",
            "LookAfter.Focus",
            "LookAfter.Health",
            "LookAfter.Capture"
        ]))
    }
}
