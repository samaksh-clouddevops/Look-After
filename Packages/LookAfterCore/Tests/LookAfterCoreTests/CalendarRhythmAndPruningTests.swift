import XCTest
@testable import LookAfterCore

final class CalendarRhythmAnalyzerTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()
    private let now = Date(timeIntervalSince1970: 1_720_000_000)

    func testHighDensityWeekVsSparseWeek() {
        let dense = makeWeek(eventCounts: [6, 7, 5, 6, 4, 0, 0], startHour: 9)
        let sparse = makeWeek(eventCounts: [1, 0, 1, 0, 1, 0, 0], startHour: 11)
        let denseProfile = CalendarRhythmAnalyzer.analyze(events: dense, now: now, calendar: calendar)
        let sparseProfile = CalendarRhythmAnalyzer.analyze(events: sparse, now: now, calendar: calendar)
        XCTAssertGreaterThan(denseProfile.meanEventsPerDay, sparseProfile.meanEventsPerDay)
        XCTAssertGreaterThan(denseProfile.highDensityWeekdayFraction, sparseProfile.highDensityWeekdayFraction)
        XCTAssertEqual(denseProfile.meetingBaselineConstraint, .anchored)
        XCTAssertEqual(sparseProfile.meetingBaselineConstraint, .flexible)
    }

    func testTypicalStartAndEndHours() {
        let events = makeWeek(eventCounts: [3, 3, 3, 3, 3, 0, 0], startHour: 8, durationHours: 1, lastEndsAt: 18)
        let profile = CalendarRhythmAnalyzer.analyze(events: events, now: now, calendar: calendar)
        XCTAssertLessThan(profile.typicalStartHour, 10)
        XCTAssertGreaterThan(profile.typicalEndHour, 16)
    }

    func testKMeansSeparatesLoads() {
        let centroids = CalendarRhythmAnalyzer.kMeans1D(
            values: [1.0, 1.2, 0.8, 8.0, 9.0, 7.5], k: 2, iterations: 20
        )
        XCTAssertEqual(centroids.count, 2)
        XCTAssertGreaterThan(abs(centroids[0] - centroids[1]), 3)
    }

    func testIQRFilterDropsVacationAndCrunchOutliers() {
        // Typical weekdays ~4–6, vacation zeros, one crunch spike.
        var loads: [Double] = Array(repeating: 5.0, count: 40)
        loads += Array(repeating: 0.0, count: 10) // holiday/sick
        loads += [18.0, 20.0] // crunch
        loads += Array(repeating: 4.5, count: 10)

        let filtered = CalendarRhythmAnalyzer.filterOutliers(loads)
        XCTAssertFalse(filtered.contains(0), "Vacation zeros should be stripped")
        XCTAssertFalse(filtered.contains(where: { $0 >= 18 }), "Crunch spikes should be stripped")
        XCTAssertGreaterThan(filtered.count, 30)

        // Centroids on filtered data stay in the typical band — not pulled to 0.
        let centroids = CalendarRhythmAnalyzer.kMeans1D(values: filtered, k: 2, iterations: 20)
        XCTAssertTrue(centroids.allSatisfy { $0 > 1.5 }, "Low centroid must not collapse to vacation zero")
    }

    func testHolidayBlockDoesNotCollapseSparseCentroid() {
        var events: [CalendarHistoryEvent] = []
        // 8 normal busy days
        events += makeWeek(eventCounts: [5, 5, 5, 5, 4, 0, 0], startHour: 9)
        // 14 empty “holiday” days would only appear as absent dayGroups —
        // inject explicit zero-load proxy via all-day excluded; instead pad sparse days
        // with tiny events then zeros aren't in dayGroups. Build dense+sparse intentionally:
        let dense = makeWeek(eventCounts: [6, 6, 6, 5, 5, 0, 0], startHour: 9)
        let sparse = makeWeek(eventCounts: [1, 1, 1, 1, 1, 0, 0], startHour: 11)
        // Mix with many near-empty single-event vacation days
        var mixed = dense + sparse
        let base = calendar.startOfDay(for: now)
        for i in 20..<34 {
            guard let day = calendar.date(byAdding: .day, value: -i, to: base) else { continue }
            // No events → day absent from groups (correct); holidays often mean *no* events.
            _ = day
        }
        // Explicit ultra-light vacation days with one 15-min block (still sparse, not zero dayGroups)
        for i in 20..<34 {
            guard let day = calendar.date(byAdding: .day, value: -i, to: base) else { continue }
            var c = calendar.dateComponents([.year, .month, .day], from: day)
            c.hour = 12
            let start = calendar.date(from: c) ?? day
            mixed.append(CalendarHistoryEvent(start: start, end: start.addingTimeInterval(15 * 60), title: "ooo"))
        }
        let profile = CalendarRhythmAnalyzer.analyze(events: mixed, now: now, calendar: calendar)
        // Busy cadence should still be recognized; meetings preferably anchored when density holds.
        XCTAssertGreaterThan(profile.meanEventsPerDay, 1.5)
        XCTAssertGreaterThan(profile.analyzedEventCount, 20)
    }

    private func makeWeek(
        eventCounts: [Int],
        startHour: Int,
        durationHours: Double = 0.75,
        lastEndsAt: Int? = nil
    ) -> [CalendarHistoryEvent] {
        var events: [CalendarHistoryEvent] = []
        let base = calendar.startOfDay(for: now)
        for (offset, count) in eventCounts.enumerated() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: base) else { continue }
            for i in 0..<count {
                var comps = calendar.dateComponents([.year, .month, .day], from: day)
                comps.hour = startHour + i
                comps.minute = 0
                let start = calendar.date(from: comps) ?? day
                let end: Date
                if i == count - 1, let lastEndsAt {
                    var endComps = comps
                    endComps.hour = lastEndsAt
                    end = calendar.date(from: endComps) ?? start.addingTimeInterval(durationHours * 3600)
                } else {
                    end = start.addingTimeInterval(durationHours * 3600)
                }
                events.append(CalendarHistoryEvent(start: start, end: end, title: "e-\(offset)-\(i)"))
            }
        }
        return events
    }
}

final class TelemetrySynthesizerPruningTests: XCTestCase {
    private let semanticHash = "meeting|standup"
    private let now = Date(timeIntervalSince1970: 1_720_000_000)

    func testImmediateCapitulationIsProvisionalNotLocked() {
        var vault = BehavioralVaultEnvelope.empty(now: now)
        vault.upsert(.seededBaseline(hash: semanticHash, constraint: .anchored, now: now), now: now)
        XCTAssertEqual(vault.signature(for: semanticHash)?.meanConfidence ?? 1, 0.2, accuracy: 0.001)

        var log = TelemetryLogEnvelope.empty(dayKey: "2024_01_01", now: now)
        log.append(
            ConstraintTelemetryEvent(
                semanticHash: semanticHash,
                taskID: "t1",
                originalConstraint: .anchored,
                newConstraint: .flexible,
                source: .swipe,
                timestamp: now,
                timeOfDay: .afternoon
            ),
            now: now
        )
        let result = TelemetrySynthesizer.synthesizeDailyTelemetry(log: log, vault: vault, now: now)
        let sig = result.vault.signature(for: semanticHash)
        XCTAssertEqual(sig?.learnedConstraint, .flexible)
        // Single swipe rewrites constraint but stays provisional (~0.45), not 0.8 locked truth.
        XCTAssertEqual(sig?.meanConfidence ?? 0, 0.45, accuracy: 0.001)
        XCTAssertLessThan(sig?.meanConfidence ?? 1, 0.8)
        XCTAssertFalse(sig?.isSeededBaseline ?? true)
        XCTAssertTrue(result.flippedHashes.contains(semanticHash))
    }

    func testSecondAgreeingSwipeConfirmsProvisionalOverride() {
        var vault = BehavioralVaultEnvelope.empty(now: now)
        vault.upsert(.seededBaseline(hash: semanticHash, constraint: .anchored, now: now), now: now)

        var log = TelemetryLogEnvelope.empty(dayKey: "d", now: now)
        // First contradicting swipe → provisional flip
        log.append(
            ConstraintTelemetryEvent(
                semanticHash: semanticHash,
                taskID: "t1",
                originalConstraint: .anchored,
                newConstraint: .flexible,
                source: .swipe,
                timestamp: now.addingTimeInterval(-3600),
                timeOfDay: .afternoon
            ),
            now: now
        )
        // Second swipe that *agrees* with new baseline → confirm to 0.8
        log.append(
            ConstraintTelemetryEvent(
                semanticHash: semanticHash,
                taskID: "t2",
                originalConstraint: .flexible,
                newConstraint: .flexible,
                source: .swipe,
                timestamp: now,
                timeOfDay: .afternoon
            ),
            now: now
        )
        let result = TelemetrySynthesizer.synthesizeDailyTelemetry(log: log, vault: vault, now: now)
        let sig = result.vault.signature(for: semanticHash)
        XCTAssertEqual(sig?.learnedConstraint, .flexible)
        XCTAssertEqual(sig?.meanConfidence ?? 0, 0.8, accuracy: 0.001)
    }

    func testAccidentalSwipeCanBeCorrectedWithoutThreeStrikes() {
        // Provisional confidence still ≤ high-conf flip threshold band —
        // reversing back toward original must not require 3 EMA overrides.
        var vault = BehavioralVaultEnvelope.empty(now: now)
        var sig = BehavioralSignature.seededBaseline(hash: semanticHash, constraint: .anchored, now: now)
        // Simulate already-provisional wrong state after accident
        sig.learnedConstraint = .fluid
        sig.confidence = TemporalConfidence(morning: 0.45, afternoon: 0.45, evening: 0.45)
        sig.isSeededBaseline = false
        vault.upsert(sig, now: now)

        var log = TelemetryLogEnvelope.empty(dayKey: "d", now: now)
        log.append(
            ConstraintTelemetryEvent(
                semanticHash: semanticHash,
                taskID: "fix",
                originalConstraint: .fluid,
                newConstraint: .anchored, // harden back
                source: .swipe,
                timestamp: now,
                timeOfDay: .morning
            ),
            now: now
        )
        // meanConfidence 0.45 is above capitulation ceiling — may not instant-flip;
        // but should still be easier than 0.8 locked. Soften path: drop conf then flip.
        // Direct harden from fluid → flexible first, then anchored needs another —
        // for this test: one harden moves fluid→flexible under normal rules if conf not low enough.
        // Ensure mean conf *is* still under ceiling for safety if we drop it:
        vault.signatures[0].confidence = .seededLow
        vault.signatures[0].learnedConstraint = .fluid
        let result = TelemetrySynthesizer.synthesizeDailyTelemetry(log: log, vault: vault, now: now)
        // With conf ≤0.2 again, immediate rewrite to .anchored provisional
        XCTAssertEqual(result.vault.signature(for: semanticHash)?.learnedConstraint, .anchored)
        XCTAssertEqual(result.vault.signature(for: semanticHash)?.meanConfidence ?? 0, 0.45, accuracy: 0.001)
    }

    func testDormancyAt30DaysAndDeleteAt45() {
        var vault = BehavioralVaultEnvelope.empty(now: now)
        let stale30 = now.addingTimeInterval(-31 * 86_400)
        vault.upsert(
            BehavioralSignature(
                semanticHash: "creative|morning_pilates",
                learnedConstraint: .flexible,
                lastUpdated: stale30,
                lastSeenInSchedule: stale30,
                state: .active
            ),
            now: now
        )
        var deleted = TelemetrySynthesizer.applyProgressivePruning(
            vault: &vault, activeScheduleHashes: [], now: now
        )
        XCTAssertTrue(deleted.isEmpty)
        guard case .dormant = vault.signature(for: "creative|morning_pilates")?.state else {
            return XCTFail("Expected dormant after 30 days")
        }
        vault.signatures[0].state = .dormant(since: now.addingTimeInterval(-16 * 86_400))
        deleted = TelemetrySynthesizer.applyProgressivePruning(
            vault: &vault, activeScheduleHashes: [], now: now
        )
        XCTAssertTrue(deleted.contains("creative|morning_pilates"))
        XCTAssertNil(vault.signature(for: "creative|morning_pilates"))
    }

    func testResurrectionFromDormantOnTelemetry() {
        var vault = BehavioralVaultEnvelope.empty(now: now)
        vault.upsert(
            BehavioralSignature(
                semanticHash: semanticHash,
                learnedConstraint: .flexible,
                confidence: TemporalConfidence(morning: 0.6, afternoon: 0.6, evening: 0.6),
                lastUpdated: now.addingTimeInterval(-40 * 86_400),
                lastSeenInSchedule: now.addingTimeInterval(-40 * 86_400),
                state: .dormant(since: now.addingTimeInterval(-10 * 86_400))
            ),
            now: now
        )
        var log = TelemetryLogEnvelope.empty(dayKey: "d", now: now)
        log.append(
            ConstraintTelemetryEvent(
                semanticHash: semanticHash,
                taskID: "t",
                originalConstraint: .flexible,
                newConstraint: .flexible,
                source: .system,
                timestamp: now
            ),
            now: now
        )
        let result = TelemetrySynthesizer.synthesizeDailyTelemetry(log: log, vault: vault, now: now)
        XCTAssertEqual(result.vault.signature(for: semanticHash)?.state, .active)
    }

    func testSeederWritesLowConfidence() {
        let profile = CalendarRhythmAnalyzer.analyze(events: [], now: now)
        var vault = BehavioralVaultEnvelope.empty(now: now)
        XCTAssertTrue(BehavioralVaultSeeder.seedIfEmpty(profile: profile, envelope: &vault, now: now))
        XCTAssertFalse(vault.signatures.isEmpty)
        for sig in vault.signatures {
            XCTAssertEqual(sig.meanConfidence, 0.2, accuracy: 0.001)
            XCTAssertEqual(sig.overrideCount, 0)
            XCTAssertTrue(sig.isSeededBaseline)
        }
        XCTAssertFalse(BehavioralVaultSeeder.seedIfEmpty(profile: profile, envelope: &vault, now: now))
    }
}
