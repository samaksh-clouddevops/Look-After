import XCTest
@testable import LookAfterCore

final class BriefingPayloadTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()
    private let now = Date(timeIntervalSince1970: 1_720_000_000)

    func testCompilerStripsTitlesUsesCategories() {
        let day = calendar.startOfDay(for: now)
        let start = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day)!
        let task = LifeTask(
            id: "1",
            title: "Call Dr. Smith about labs",
            status: .pending,
            estimatedMinutes: 30,
            scheduledDate: day,
            scheduledTime: start,
            timeConstraint: .anchored,
            scheduledEndTime: start.addingTimeInterval(1800),
            userId: "u"
        )
        let payload = BriefingPayloadCompiler.compile(
            .init(
                now: now,
                energy: .low,
                energyPercent: 40,
                capacityBandLabel: "Low Capacity",
                tasks: [task],
                nextEventTitle: "Call Dr. Smith about labs",
                minutesUntilNextEvent: 45
            ),
            calendar: calendar
        )
        XCTAssertEqual(payload.nextEventCategory, "medical appointment")
        XCTAssertEqual(payload.anchoredCount, 1)
        XCTAssertFalse(payload.structureFingerprint.isEmpty)
        // Deterministic narrative must not contain the doctor name.
        let narrative = payload.deterministicNarrative(userName: "Alex")
        XCTAssertFalse(narrative.lowercased().contains("smith"))
        XCTAssertTrue(narrative.lowercased().contains("medical") || narrative.contains("anchored"))
    }

    func testMutationsCollapsedAndNarrativeMentionsSabotage() {
        let day = calendar.startOfDay(for: now)
        let recovery = LifeTask(
            id: "r",
            title: "Recovery block",
            status: .pending,
            estimatedMinutes: 90,
            scheduledDate: day,
            scheduledTime: now,
            tags: ["recovery-block"],
            timeConstraint: .anchored,
            userId: "u"
        )
        let payload = BriefingPayloadCompiler.compile(
            .init(
                now: now,
                capacityBandLabel: "Good Capacity",
                tasks: [recovery],
                cascadeDecisions: [
                    .init(taskID: "a", action: .shiftLater, reason: "x"),
                    .init(taskID: "b", action: .shiftLater, reason: "y"),
                    .init(taskID: "c", action: .park, reason: "z"),
                ]
            ),
            calendar: calendar
        )
        XCTAssertTrue(payload.hasRecoveryBlockToday)
        XCTAssertTrue(payload.mutations.contains { $0.code == "sabotage_recovery" })
        XCTAssertEqual(payload.mutations.first { $0.code == "shift_later" }?.count, 2)
        let text = payload.deterministicNarrative()
        XCTAssertTrue(text.lowercased().contains("recovery"))
    }

    func testFingerprintChangesOnMutation() {
        var a = BriefingPayload(
            dayKey: "2024_01_01",
            energyState: "Moderate",
            capacityBand: "Good",
            anchoredCount: 2
        )
        var b = a
        b.mutations = [.init(code: "park", count: 1)]
        b.structureFingerprint = BriefingPayload.fingerprint(for: b)
        XCTAssertNotEqual(a.structureFingerprint, b.structureFingerprint)
    }

    func testPIISanitizer() {
        XCTAssertEqual(BriefingPIISanitizer.category(forTitle: "Therapy with Jane"), "medical appointment")
        XCTAssertEqual(BriefingPIISanitizer.category(forTitle: "Standup"), "meeting")
        let scrubbed = BriefingPIISanitizer.scrub("email me at a@b.com or 555-123-4567")
        XCTAssertFalse(scrubbed.contains("@"))
        XCTAssertTrue(scrubbed.contains("[email]"))
        XCTAssertTrue(scrubbed.contains("[phone]"))
    }

    func testSnapshotChipsIncludeEnergyAndAnchored() {
        let payload = BriefingPayload(
            dayKey: "d",
            energyState: "Low",
            energyPercent: 40,
            capacityBand: "Low Capacity",
            anchoredCount: 3,
            focusMinutes: 120
        )
        let chips = payload.snapshotChips()
        XCTAssertTrue(chips.contains { $0.id == "energy" && $0.value == "40%" })
        XCTAssertTrue(chips.contains { $0.id == "anchored" && $0.value == "3" })
        XCTAssertTrue(chips.contains { $0.id == "focus" })
    }

    func testDeterministicCapsAtFourSentences() {
        let payload = BriefingPayload(
            dayKey: "d",
            energyState: "Peak",
            capacityBand: "Peak Focus",
            anchoredCount: 2,
            flexibleCount: 1,
            focusMinutes: 90,
            remainingTaskCount: 4,
            mutations: [.init(code: "shift_later", count: 2)],
            somedayDecayCount: 5,
            nextEventCategory: "meeting",
            minutesUntilNextEvent: 30
        )
        let text = payload.deterministicNarrative(userName: "Sam")
        let sentences = text.components(separatedBy: ". ").filter { !$0.isEmpty }
        XCTAssertLessThanOrEqual(sentences.count, 4)
    }

    func testRouterPayloadMatchesPhaseContract() {
        let router = BriefingRouterPayload(
            energyState: "Recovery",
            anchoredCommitmentsCount: 2,
            fluidHoursAvailable: 2.0,
            systemActions: [
                "Triggered a Sabotage Auction to enforce a 90-minute recovery block.",
                "Parked 2 flexible tasks to resolve afternoon crowding.",
                "Superseded yesterday's uncompleted workout to prevent double-booking today.",
                "email secret@clinic.org"
            ],
            decayedTaskCount: 1,
            supersededTaskCount: 1,
            expiredTaskCount: 1
        )
        XCTAssertEqual(router.energyState, "Recovery")
        XCTAssertEqual(router.anchoredCommitmentsCount, 2)
        XCTAssertEqual(router.fluidHoursAvailable, 2.0, accuracy: 0.01)
        XCTAssertEqual(router.decayedTaskCount, 1)
        XCTAssertEqual(router.supersededTaskCount, 1)
        XCTAssertEqual(router.expiredTaskCount, 1)
        XCTAssertFalse(router.systemActions.joined().contains("@"))
        let chips = router.snapshotChips()
        XCTAssertTrue(chips.contains { $0.id == "expired" })
        XCTAssertTrue(chips.contains { $0.id == "superseded" })
    }

    func testCascadeDistillerIgnoresMicroShiftsAndGroupsParks() {
        let decisions: [ConflictCascadeDecision] = [
            .init(taskID: "1", action: .shiftLater, reason: "x", shiftMinutes: 15), // ignore
            .init(taskID: "2", action: .shiftLater, reason: "y", shiftMinutes: 45),
            .init(taskID: "3", action: .shiftLater, reason: "z", shiftMinutes: 60),
            .init(taskID: "4", action: .compress, reason: "c", compressHitViableFloor: false, compressDeltaMinutes: 5),
            .init(taskID: "5", action: .compress, reason: "c2", compressHitViableFloor: true, compressDeltaMinutes: 20),
            .init(taskID: "6", action: .park, reason: "p"),
            .init(taskID: "7", action: .park, reason: "p2"),
            .init(taskID: "8", action: .park, reason: "p3"),
        ]
        let actions = CascadeDistiller.distill(
            decisions: decisions,
            triggeredRecoveryLock: true,
            resurrectedCount: 0
        )
        XCTAssertTrue(actions.contains { $0.lowercased().contains("sabotage") })
        XCTAssertTrue(actions.contains { $0.contains("Parked 3") })
        XCTAssertTrue(actions.contains { $0.lowercased().contains("several afternoon") })
        XCTAssertTrue(actions.contains { $0.lowercased().contains("viable duration") })
        // Must not enumerate seven frantic micro-events
        XCTAssertLessThanOrEqual(actions.count, 5)
        XCTAssertFalse(actions.contains { $0.contains("15") })
    }

    func testCascadeDistillerSilentWhenOnlyMicroAdjustments() {
        let decisions: [ConflictCascadeDecision] = [
            .init(taskID: "1", action: .shiftLater, reason: "x", shiftMinutes: 10),
            .init(taskID: "2", action: .shiftLater, reason: "y", shiftMinutes: 20),
            .init(taskID: "3", action: .compress, reason: "c", compressHitViableFloor: false),
            .init(taskID: "4", action: .keep, reason: "ok"),
        ]
        let actions = CascadeDistiller.distill(decisions: decisions)
        XCTAssertTrue(actions.isEmpty, "Micro-only cascade must not panic the briefing")
    }

    func testRouterPayloadFromFullMapsMutationsWithoutTitles() {
        let full = BriefingPayload(
            dayKey: "2024_01_01",
            energyState: "Low",
            capacityBand: "Low Capacity",
            anchoredCount: 3,
            focusMinutes: 90,
            mutations: [
                .init(code: "sabotage_recovery", count: 1),
                .init(code: "shift_later", count: 2)
            ],
            telemetryLearnings: ["email me at secret@clinic.org"],
            somedayDecayCount: 2
        )
        let router = BriefingRouterPayload(from: full)
        XCTAssertEqual(router.anchoredCommitmentsCount, 3)
        XCTAssertEqual(router.decayedTaskCount, 2)
        XCTAssertTrue(router.systemActions.contains { $0.lowercased().contains("sabotage") })
        XCTAssertFalse(router.systemActions.joined().contains("@"))
    }
}
