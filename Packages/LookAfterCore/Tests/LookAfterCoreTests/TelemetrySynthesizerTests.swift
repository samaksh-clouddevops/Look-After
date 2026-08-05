import XCTest
@testable import LookAfterCore

final class TelemetrySynthesizerTests: XCTestCase {

    private let hash = "physicalactivity|gym_push_day"
    private let now = Date(timeIntervalSince1970: 1_720_000_000)

    func testSofteningOverridesFlipBaselineAcrossSealedDays() {
        var vault = BehavioralVaultEnvelope.empty(now: now)
        vault.upsert(
            BehavioralSignature(
                semanticHash: hash,
                learnedConstraint: .anchored,
                confidence: .high,
                lastUpdated: now.addingTimeInterval(-200_000)
            ),
            now: now
        )

        var dayA = TelemetryLogEnvelope.empty(dayKey: "2024_01_01", now: now)
        var dayB = TelemetryLogEnvelope.empty(dayKey: "2024_01_03", now: now)
        for i in 0..<5 {
            let event = ConstraintTelemetryEvent(
                semanticHash: hash,
                taskID: "task-\(i)",
                originalConstraint: .anchored,
                newConstraint: .flexible,
                source: .swipe,
                timestamp: now.addingTimeInterval(Double(-i) * 3_600),
                timeOfDay: .afternoon
            )
            if i < 3 { dayA.append(event, now: now) } else { dayB.append(event, now: now) }
        }

        let result = TelemetrySynthesizer.synthesizeDailyTelemetry(
            sealedLogs: [("2024_01_01", dayA), ("2024_01_03", dayB)],
            vault: vault,
            now: now
        )

        XCTAssertEqual(result.vault.signature(for: hash)?.learnedConstraint, .flexible)
        XCTAssertTrue(result.flippedHashes.contains(hash))
        XCTAssertEqual(result.processedEventCount, 5)
        XCTAssertEqual(result.consumedDayKeys, ["2024_01_01", "2024_01_03"])
    }

    func testAfternoonSofteningDecaysPrimaryHarderThanOthers() {
        var vault = BehavioralVaultEnvelope.empty(now: now)
        vault.upsert(
            BehavioralSignature(
                semanticHash: hash,
                learnedConstraint: .anchored,
                confidence: TemporalConfidence(morning: 0.8, afternoon: 0.8, evening: 0.8)
            ),
            now: now
        )
        var log = TelemetryLogEnvelope.empty(dayKey: "2024_01_01", now: now)
        log.append(
            ConstraintTelemetryEvent(
                semanticHash: hash,
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
        let conf = result.vault.signature(for: hash)!.confidence
        XCTAssertLessThan(conf.afternoon, conf.morning)
        XCTAssertEqual(conf.morning, conf.evening, accuracy: 0.001)
        XCTAssertEqual(result.vault.signature(for: hash)?.learnedConstraint, .anchored)
    }

    func testPrunesAbandonedSignaturesAfter45Days() {
        var vault = BehavioralVaultEnvelope.empty(now: now)
        let stale = now.addingTimeInterval(-50 * 86_400)
        // Already dormant long enough that progressive pruning deletes (45d total).
        vault.upsert(
            BehavioralSignature(
                semanticHash: "creative|morning_pilates",
                learnedConstraint: .flexible,
                lastUpdated: stale,
                lastSeenInSchedule: stale,
                state: .dormant(since: now.addingTimeInterval(-20 * 86_400))
            ),
            now: now
        )
        vault.upsert(
            BehavioralSignature(
                semanticHash: hash,
                learnedConstraint: .anchored,
                lastUpdated: now,
                lastSeenInSchedule: now,
                state: .active
            ),
            now: now
        )

        let result = TelemetrySynthesizer.synthesizeDailyTelemetry(
            sealedLogs: [],
            vault: vault,
            activeScheduleHashes: [hash],
            now: now
        )
        XCTAssertNil(result.vault.signature(for: "creative|morning_pilates"))
        XCTAssertNotNil(result.vault.signature(for: hash))
        XCTAssertTrue(result.prunedHashes.contains("creative|morning_pilates"))
    }

    func testDoubleBufferSealedOnly() {
        let today = TelemetryLogEnvelope.empty(dayKey: "2024_06_10", now: now)
        var sealed = TelemetryLogEnvelope.empty(dayKey: "2024_06_09", now: now)
        sealed.append(
            ConstraintTelemetryEvent(
                semanticHash: hash,
                taskID: "t",
                originalConstraint: .flexible,
                newConstraint: .fluid,
                source: .swipe,
                timestamp: now.addingTimeInterval(-86_400)
            ),
            now: now
        )
        let logger = InteractionTelemetryLogger.inMemory(
            seed: today,
            sealed: ["2024_06_09": sealed]
        )
        XCTAssertEqual(logger.snapshot().dayKey, "2024_06_10")
        XCTAssertEqual(logger.sealedLogs(excludingDayKey: nil).count, 1)
        XCTAssertEqual(logger.sealedLogs(excludingDayKey: nil).first?.dayKey, "2024_06_09")
    }

    func testStarvationDetection() {
        var vault = BehavioralVaultEnvelope.empty(now: now.addingTimeInterval(-60 * 60 * 60))
        vault.updatedAt = now.addingTimeInterval(-60 * 60 * 60)
        XCTAssertTrue(TelemetrySynthesizer.isStarved(vault: vault, now: now))
        vault.updatedAt = now.addingTimeInterval(-10 * 60 * 60)
        XCTAssertFalse(TelemetrySynthesizer.isStarved(vault: vault, now: now))
    }

    func testAmnesiaResetsSignature() {
        var vault = BehavioralVaultEnvelope.empty(now: now)
        vault.upsert(BehavioralSignature(semanticHash: hash, learnedConstraint: .fluid), now: now)
        XCTAssertTrue(BehavioralAmnesia.resetSignature(for: hash, envelope: &vault, now: now))
        XCTAssertNil(vault.signature(for: hash))
    }
}
