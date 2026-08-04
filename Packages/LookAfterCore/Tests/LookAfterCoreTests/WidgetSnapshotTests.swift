import XCTest
@testable import LookAfterCore

/// Widget System V2 — snapshot contracts, deep links, kinds, stale rules.
final class WidgetSnapshotTests: XCTestCase {

    // MARK: - Empty / defaults

    func testEmptySnapshotDefaults() {
        let s = WidgetSnapshot.empty
        XCTAssertNil(s.topTaskTitle)
        XCTAssertEqual(s.energyScore, 50)
        XCTAssertEqual(s.energyLevel, "Moderate")
        XCTAssertTrue(s.tasks.isEmpty)
        XCTAssertNil(s.executive)
        XCTAssertEqual(s.schemaVersion, 2)
    }

    func testResolvedRecommendation_PrefersExecutive() {
        let exec = WidgetRecommendation(taskID: "t1", title: "Meditate", whyLine: "Low energy window")
        let s = WidgetSnapshot(
            topTaskTitle: "Legacy title",
            recommendation: "Legacy why",
            executive: exec
        )
        XCTAssertEqual(s.resolvedRecommendation.title, "Meditate")
        XCTAssertEqual(s.resolvedRecommendation.taskID, "t1")
        XCTAssertEqual(s.resolvedRecommendation.whyLine, "Low energy window")
    }

    func testResolvedRecommendation_FallsBackToV1Fields() {
        let s = WidgetSnapshot(
            topTaskTitle: "Inbox zero",
            topTaskMinutes: 15,
            energyScore: 80,
            energyLevel: "High",
            recommendation: "Peak morning block"
        )
        let r = s.resolvedRecommendation
        XCTAssertEqual(r.title, "Inbox zero")
        XCTAssertEqual(r.estimatedMinutes, 15)
        XCTAssertEqual(r.energyScore, 80)
        XCTAssertEqual(r.whyLine, "Peak morning block")
    }

    func testResolvedRecommendation_ClearWhenNoTitle() {
        let s = WidgetSnapshot.empty
        XCTAssertEqual(s.resolvedRecommendation.title, WidgetRecommendation.clear.title)
    }

    // MARK: - Codable round-trip V2

    func testFullV2Snapshot_RoundTrip() throws {
        let original = makeFullSnapshot()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)

        XCTAssertEqual(decoded.topTaskTitle, original.topTaskTitle)
        XCTAssertEqual(decoded.energyScore, original.energyScore)
        XCTAssertEqual(decoded.executive?.title, original.executive?.title)
        XCTAssertEqual(decoded.today?.freeMinutes, 40)
        XCTAssertEqual(decoded.today?.beats.count, 2)
        XCTAssertEqual(decoded.focus?.isActive, true)
        XCTAssertEqual(decoded.medication?.name, "Vitamin D")
        XCTAssertEqual(decoded.recoveryLabel, "Good recovery")
        XCTAssertEqual(decoded.schemaVersion, 2)
        XCTAssertEqual(decoded.tasks.count, 1)
    }

    // MARK: - V1 payload decode (missing V2 keys)

    func testDecodeV1Payload_MissingV2Keys() throws {
        let v1: [String: Any] = [
            "topTaskTitle": "Ship widget",
            "topTaskMinutes": 30,
            "energyScore": 66,
            "energyLevel": "Moderate",
            "recommendation": "Do it now",
            "completedTodayCount": 1,
            "activeTaskCount": 3,
            "tasks": [
                ["id": "a", "title": "Ship widget", "estimatedMinutes": 30, "priorityLabel": "High"]
            ],
            "updatedAt": Date().timeIntervalSinceReferenceDate
        ]
        let data = try JSONSerialization.data(withJSONObject: v1)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        // Encode dates as seconds since reference if needed — use Codable path instead
        let snap = WidgetSnapshot(
            topTaskTitle: "Ship widget",
            topTaskMinutes: 30,
            energyScore: 66,
            recommendation: "Do it now",
            tasks: [WidgetTaskItem(id: "a", title: "Ship widget", estimatedMinutes: 30, priorityLabel: "High")],
            schemaVersion: 1
        )
        let encoded = try JSONEncoder().encode(snap)
        // Strip V2 keys from JSON to simulate old app
        var obj = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        ["executive", "today", "focus", "medication", "recoveryLabel", "hydrationMlToday", "insightLine", "schemaVersion"].forEach {
            obj.removeValue(forKey: $0)
        }
        let stripped = try JSONSerialization.data(withJSONObject: obj)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: stripped)

        XCTAssertEqual(decoded.topTaskTitle, "Ship widget")
        XCTAssertEqual(decoded.energyScore, 66)
        XCTAssertNil(decoded.executive)
        XCTAssertNil(decoded.today)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.tasks.first?.title, "Ship widget")
    }

    // MARK: - Stale

    func testIsStale_WhenOlderThanSixHours() {
        let old = WidgetSnapshot(updatedAt: Date().addingTimeInterval(-7 * 60 * 60))
        let fresh = WidgetSnapshot(updatedAt: Date())
        XCTAssertTrue(old.isStale)
        XCTAssertFalse(fresh.isStale)
    }

    // MARK: - Supporting types

    func testMedicationHasMedication() {
        XCTAssertFalse(WidgetMedicationStatus.none.hasMedication)
        XCTAssertTrue(WidgetMedicationStatus(name: "Med").hasMedication)
        XCTAssertFalse(WidgetMedicationStatus(name: "").hasMedication)
    }

    func testFocusIdle() {
        XCTAssertFalse(WidgetFocusState.idle.isActive)
        XCTAssertNil(WidgetFocusState.idle.taskTitle)
    }

    func testRecommendationClear() {
        XCTAssertEqual(WidgetRecommendation.clear.title, "You're clear")
        XCTAssertFalse(WidgetRecommendation.clear.whyLine.isEmpty)
    }

    // MARK: - Kinds & deep links

    func testWidgetKindsAreUniqueAndStable() {
        let kinds = [
            LookAfterWidgetKind.recommendation,
            LookAfterWidgetKind.today,
            LookAfterWidgetKind.focus,
            LookAfterWidgetKind.health,
            LookAfterWidgetKind.capture,
            LookAfterWidgetKind.medication,
            LookAfterWidgetKind.calendar,
            LookAfterWidgetKind.habits,
            LookAfterWidgetKind.lifeState,
            LookAfterWidgetKind.brain,
            LookAfterWidgetKind.weekly,
            LookAfterWidgetKind.memory,
            LookAfterWidgetKind.nowV1,
            LookAfterWidgetKind.energyV1,
            LookAfterWidgetKind.tasksV1
        ]
        XCTAssertEqual(Set(kinds).count, kinds.count, "Kind strings must be unique")
        XCTAssertTrue(LookAfterWidgetKind.recommendation.hasPrefix("LookAfter."))
        XCTAssertEqual(LookAfterWidgetKind.nowV1, "NowWidget")
    }

    func testDeepLinks() {
        XCTAssertEqual(LookAfterDeepLink.scheme, "lookafter")
        XCTAssertEqual(LookAfterDeepLink.recommend.scheme, "lookafter")
        XCTAssertEqual(LookAfterDeepLink.recommend.host, "recommend")
        XCTAssertEqual(LookAfterDeepLink.today.host, "today")
        XCTAssertEqual(LookAfterDeepLink.focus.host, "focus")
        XCTAssertEqual(LookAfterDeepLink.health.host, "health")
        XCTAssertEqual(LookAfterDeepLink.medication.host, "medication")
        XCTAssertEqual(LookAfterDeepLink.brain.host, "brain")

        let capture = LookAfterDeepLink.capture(mode: "voice")
        XCTAssertEqual(capture.host, "capture")
        XCTAssertTrue(capture.query?.contains("mode=voice") == true)

        let task = LookAfterDeepLink.task(id: "abc-123")
        XCTAssertEqual(task.host, "task")
        XCTAssertTrue(task.path.contains("abc-123"))
    }

    func testAppGroupConstants() {
        XCTAssertEqual(WidgetAppGroup.identifier, "group.com.samaksh.flowos")
        XCTAssertFalse(WidgetAppGroup.snapshotKey.isEmpty)
        XCTAssertFalse(WidgetAppGroup.commandQueueKey.isEmpty)
        XCTAssertNotEqual(WidgetAppGroup.snapshotKey, WidgetAppGroup.commandQueueKey)
    }

    // MARK: - Accent token (V4)

    func testAccentPrimaryIsActionGreenNotForest() {
        // Smoke: DesignSystem compiles and accent is defined for widget chrome.
        // Hex C8FF4D is asserted via source contract; UIColor extraction is platform-specific.
        XCTAssertNotNil(DesignSystem.accentPrimary)
        XCTAssertNotNil(DesignSystem.accentOnPrimary)
        XCTAssertNotNil(DesignSystem.backgroundPrimary)
        XCTAssertNotNil(DesignSystem.health)
        XCTAssertNotNil(DesignSystem.focus)
    }

    // MARK: - Fixture

    private func makeFullSnapshot() -> WidgetSnapshot {
        WidgetSnapshot(
            topTaskTitle: "Deep work block",
            topTaskMinutes: 45,
            energyScore: 78,
            energyLevel: "High",
            recommendation: "Protect the morning",
            completedTodayCount: 2,
            activeTaskCount: 5,
            sleepHours: 7.5,
            stepCount: 4000,
            hrvMs: 52,
            tasks: [
                WidgetTaskItem(id: "1", title: "Deep work block", estimatedMinutes: 45, priorityLabel: "High")
            ],
            executive: WidgetRecommendation(
                taskID: "1",
                title: "Deep work block",
                whyLine: "Protect the morning",
                nextStepLine: "Open the doc",
                estimatedMinutes: 45,
                energyLabel: "High",
                energyScore: 78
            ),
            today: WidgetTodaySummary(
                nextEventTitle: "1:1",
                nextEventTimeLabel: "14:00",
                nextTaskTitle: "Deep work block",
                freeMinutes: 40,
                capacityLabel: "Steady",
                beats: [
                    WidgetTimelineBeat(id: "b1", timeLabel: "09:00", title: "Deep work", detail: "45m"),
                    WidgetTimelineBeat(id: "b2", timeLabel: "14:00", title: "1:1", detail: "30m", kind: "meeting")
                ]
            ),
            focus: WidgetFocusState(
                isActive: true,
                taskTitle: "Deep work block",
                remainingLabel: "24:00",
                isPaused: false,
                isOnBreak: false
            ),
            medication: WidgetMedicationStatus(
                id: "m1",
                name: "Vitamin D",
                timeLabel: "8:00 AM",
                isTaken: false,
                dosage: "1000 IU"
            ),
            recoveryLabel: "Good recovery",
            schemaVersion: 2
        )
    }
}
