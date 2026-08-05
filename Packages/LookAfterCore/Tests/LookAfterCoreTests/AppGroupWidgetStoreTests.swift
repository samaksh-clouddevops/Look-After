import XCTest
@testable import LookAfterCore

final class AppGroupWidgetStoreTests: XCTestCase {
    func testSnapshotRoundTripViaFileURL() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("widget-snapshot.json")
        let snapshot = WidgetSnapshot(
            topTaskTitle: "Review notes",
            energyScore: 72,
            energyLevel: "Good",
            recommendation: "Focus while energy is up.",
            completedTodayCount: 2,
            activeTaskCount: 4,
            sleepHours: 7.1,
            stepCount: 3500
        )

        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: [.atomic])

        let loaded = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(contentsOf: url))
        XCTAssertEqual(loaded.topTaskTitle, snapshot.topTaskTitle)
        XCTAssertEqual(loaded.energyScore, snapshot.energyScore)
        XCTAssertEqual(loaded.sleepHours, snapshot.sleepHours)
    }

    func testLoadReturnsEmptyWhenContainerUnavailableInTestHost() {
        // Unit test host has no App Group entitlements — must not crash.
        let snapshot = AppGroupWidgetStore.load()
        XCTAssertNil(snapshot.topTaskTitle)
        XCTAssertEqual(snapshot.energyScore, 50)
    }
}
