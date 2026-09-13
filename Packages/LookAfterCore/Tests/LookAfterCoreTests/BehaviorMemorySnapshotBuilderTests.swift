import XCTest
@testable import LookAfterCore

final class PlanningPromptBehaviorContextBlockTests: XCTestCase {
    // Uses BehaviorMemorySnapshot's memberwise-style public init (see BehaviorMemorySnapshot.swift).

    private func snapshot(
        typicalDeepWorkHour: Int? = nil,
        typicalDeepWorkHourConfidence: PatternConfidence? = nil,
        typicalDeepWorkHourSampleCount: Int? = nil,
        preferredFlowDurationMinutes: Int? = nil,
        preferredFlowDurationConfidence: PatternConfidence? = nil,
        preferredFlowDurationSampleCount: Int? = nil
    ) -> BehaviorMemorySnapshot {
        BehaviorMemorySnapshot(
            patterns: [],
            deferralRecords: [],
            preferredFlowDurationMinutes: preferredFlowDurationMinutes,
            preferredFlowDurationSampleCount: preferredFlowDurationSampleCount,
            preferredFlowDurationConfidence: preferredFlowDurationConfidence,
            typicalDeepWorkHour: typicalDeepWorkHour,
            typicalDeepWorkHourSampleCount: typicalDeepWorkHourSampleCount,
            typicalDeepWorkHourConfidence: typicalDeepWorkHourConfidence,
            recordedEventCount: 0,
            completionEventCount: 0,
            deferralEventCount: 0,
            flowSessionEventCount: 0,
            updatedAt: Date()
        )
    }

    func testNilSnapshotProducesEmptyBlock() {
        XCTAssertEqual(PlanningPromptContextBuilder.behaviorContextBlock(nil), "")
    }

    func testLowConfidenceIsOmitted() {
        let snap = snapshot(
            typicalDeepWorkHour: 9,
            typicalDeepWorkHourConfidence: .low,
            typicalDeepWorkHourSampleCount: 6
        )
        XCTAssertEqual(PlanningPromptContextBuilder.behaviorContextBlock(snap), "")
    }

    func testMediumConfidenceIsSurfaced() {
        let snap = snapshot(
            typicalDeepWorkHour: 9,
            typicalDeepWorkHourConfidence: .medium,
            typicalDeepWorkHourSampleCount: 15
        )
        let block = PlanningPromptContextBuilder.behaviorContextBlock(snap)
        XCTAssertTrue(block.contains("9:00"))
        XCTAssertTrue(block.contains("15 occurrences"))
    }

    func testHighConfidenceDurationIsSurfaced() {
        let snap = snapshot(
            preferredFlowDurationMinutes: 45,
            preferredFlowDurationConfidence: .high,
            preferredFlowDurationSampleCount: 20
        )
        let block = PlanningPromptContextBuilder.behaviorContextBlock(snap)
        XCTAssertTrue(block.contains("45 minutes"))
    }

    func testMissingSampleCountOmitsLineEvenAtHighConfidence() {
        let snap = snapshot(
            typicalDeepWorkHour: 9,
            typicalDeepWorkHourConfidence: .high,
            typicalDeepWorkHourSampleCount: nil
        )
        XCTAssertEqual(PlanningPromptContextBuilder.behaviorContextBlock(snap), "")
    }
}

final class BehaviorMemorySnapshotBuilderTests: XCTestCase {

    // MARK: - Fixtures

    private func context(hourOfDay: Int) -> BehaviorContextMetadata {
        BehaviorContextMetadata(
            energyScore: 0.5,
            flowPersonality: .steady,
            timeOfDay: .afternoon,
            hourOfDay: hourOfDay,
            dayOfWeek: 3,
            weather: .clear,
            sleepQuality: .good,
            focusModeEnabled: false,
            isWeekend: false
        )
    }

    private func completion(hour: Int, durationMinutes: Int) -> BehaviorEvent {
        BehaviorEvent(
            kind: .taskCompletion,
            durationMinutes: durationMinutes,
            context: context(hourOfDay: hour)
        )
    }

    private func flowSession(durationMinutes: Int) -> BehaviorEvent {
        BehaviorEvent(
            kind: .flowSessionEnded,
            durationMinutes: durationMinutes,
            context: context(hourOfDay: 10)
        )
    }

    // MARK: - typicalDeepWorkHour

    func testEmptyHistoryYieldsNilHour() {
        let snapshot = BehaviorMemorySnapshotBuilder.build(from: [])
        XCTAssertNil(snapshot.typicalDeepWorkHour)
        XCTAssertNil(snapshot.typicalDeepWorkHourSampleCount)
        XCTAssertNil(snapshot.typicalDeepWorkHourConfidence)
    }

    func testBelowThresholdSampleCountYieldsNilHour() {
        // Only 4 qualifying events, threshold is 5.
        let events = (0..<4).map { _ in completion(hour: 9, durationMinutes: 30) }
        let snapshot = BehaviorMemorySnapshotBuilder.build(from: events)
        XCTAssertNil(snapshot.typicalDeepWorkHour)
    }

    func testShortTasksDoNotCountTowardHour() {
        // 10 events at hour 9, but all below the 30-minute threshold.
        let events = (0..<10).map { _ in completion(hour: 9, durationMinutes: 15) }
        let snapshot = BehaviorMemorySnapshotBuilder.build(from: events)
        XCTAssertNil(snapshot.typicalDeepWorkHour)
    }

    func testHighCountLowConcentrationYieldsLowConfidence() {
        // 15 events spread roughly evenly across 3 hours -> concentration ~0.33 (< 0.4).
        var events: [BehaviorEvent] = []
        for hour in [9, 12, 15] {
            events += (0..<5).map { _ in completion(hour: hour, durationMinutes: 30) }
        }
        // Break the exact tie by giving hour 9 one extra event (mode = 9, count 6/16 = 0.375).
        events.append(completion(hour: 9, durationMinutes: 30))

        let snapshot = BehaviorMemorySnapshotBuilder.build(from: events)
        XCTAssertEqual(snapshot.typicalDeepWorkHour, 9)
        XCTAssertEqual(snapshot.typicalDeepWorkHourSampleCount, 16)
        XCTAssertEqual(snapshot.typicalDeepWorkHourConfidence, .low)
    }

    func testHighCountHighConcentrationYieldsHighConfidence() {
        // 15 events at hour 9, 3 events at hour 14 -> concentration 15/18 = 0.83 (> 0.6).
        var events = (0..<15).map { _ in completion(hour: 9, durationMinutes: 30) }
        events += (0..<3).map { _ in completion(hour: 14, durationMinutes: 30) }

        let snapshot = BehaviorMemorySnapshotBuilder.build(from: events)
        XCTAssertEqual(snapshot.typicalDeepWorkHour, 9)
        XCTAssertEqual(snapshot.typicalDeepWorkHourSampleCount, 18)
        XCTAssertEqual(snapshot.typicalDeepWorkHourConfidence, .high)
    }

    func testTiedModeCountsYieldNilDeterministically() {
        // 5 events at hour 9, 5 events at hour 18 -> tie, no fabricated preference.
        var events = (0..<5).map { _ in completion(hour: 9, durationMinutes: 30) }
        events += (0..<5).map { _ in completion(hour: 18, durationMinutes: 30) }

        for _ in 0..<5 {
            let snapshot = BehaviorMemorySnapshotBuilder.build(from: events)
            XCTAssertNil(snapshot.typicalDeepWorkHour)
            XCTAssertNil(snapshot.typicalDeepWorkHourSampleCount)
            XCTAssertNil(snapshot.typicalDeepWorkHourConfidence)
        }
    }

    // MARK: - preferredFlowDurationMinutes

    func testEmptyHistoryYieldsNilDuration() {
        let snapshot = BehaviorMemorySnapshotBuilder.build(from: [])
        XCTAssertNil(snapshot.preferredFlowDurationMinutes)
        XCTAssertNil(snapshot.preferredFlowDurationSampleCount)
        XCTAssertNil(snapshot.preferredFlowDurationConfidence)
    }

    func testBelowThresholdSampleCountYieldsNilDuration() {
        let events = (0..<4).map { _ in flowSession(durationMinutes: 25) }
        let snapshot = BehaviorMemorySnapshotBuilder.build(from: events)
        XCTAssertNil(snapshot.preferredFlowDurationMinutes)
    }

    func testMedianDurationComputedCorrectlyForOddCount() {
        let events = [10, 20, 30, 40, 50].map { flowSession(durationMinutes: $0) }
        let snapshot = BehaviorMemorySnapshotBuilder.build(from: events)
        XCTAssertEqual(snapshot.preferredFlowDurationMinutes, 30)
        XCTAssertEqual(snapshot.preferredFlowDurationSampleCount, 5)
    }

    func testMedianDurationComputedCorrectlyForEvenCount() {
        let events = [10, 20, 30, 40].map { flowSession(durationMinutes: $0) }
        let snapshot = BehaviorMemorySnapshotBuilder.build(from: events)
        // (20 + 30) / 2 = 25
        XCTAssertEqual(snapshot.preferredFlowDurationMinutes, 25)
    }

    func testConcentratedDurationsYieldHighConfidence() {
        // 15 sessions all in the same 15-minute bucket (25-29 min) -> concentration 1.0.
        let events = (0..<15).map { _ in flowSession(durationMinutes: 25) }
        let snapshot = BehaviorMemorySnapshotBuilder.build(from: events)
        XCTAssertEqual(snapshot.preferredFlowDurationConfidence, .high)
    }
}
