import XCTest
@testable import LookAfterCore

final class TaskScheduleQueryTests: XCTestCase {

    func testSupersededDuplicateIDsPreferScheduledOccurrence() {
        let day = Calendar.current.startOfDay(for: Date())
        let templateId = "template-1"
        var parked = LifeTask(
            id: "parked-1",
            title: "Brush teeth — evening",
            schedulingMode: .flexible,
            userId: "user-1"
        )
        parked.parentTaskId = templateId
        var occurrence = LifeTask(
            id: "occ-1",
            title: "Brush teeth — evening",
            scheduledDate: day,
            scheduledTime: Calendar.current.date(bySettingHour: 21, minute: 30, second: 0, of: day),
            schedulingMode: .fixedTime,
            userId: "user-1"
        )
        occurrence.parentTaskId = templateId

        let stale = TaskScheduleQuery.supersededDuplicateIDs(in: [parked, occurrence], on: day)
        XCTAssertEqual(stale, ["parked-1"])
    }

    func testEphemeralityEnrichAddsMealSemantics() {
        let task = LifeTask(
            title: "Breakfast",
            tags: ["daily-routine", "onboarding"],
            recurrence: .daily,
            userId: "user-1"
        )

        let enriched = TaskEphemeralityDefaults.enrich(task)
        XCTAssertEqual(enriched.expirationPolicy, .endOfDay)
        XCTAssertEqual(enriched.collisionStrategy, .dropOldest)
        XCTAssertEqual(enriched.semanticProfile?.semanticType, .errand)
        XCTAssertEqual(enriched.semanticProfile?.subtype, "meal")
    }
}

final class LifeTimelineKindResolverTests: XCTestCase {

    func testBrushTeethAlwaysHabitEvenWithPersonalLifeArea() {
        let task = LifeTask(
            title: "Brush teeth — evening",
            lifeArea: .personal,
            tags: ["daily-routine"],
            userId: "user-1"
        )
        XCTAssertEqual(LifeTimelineKindResolver.kind(for: task), .habit)
    }

    func testBrushTeethNotRecoveryWithStoredGenericProfile() {
        var task = LifeTask(
            title: "Brush teeth — morning",
            lifeArea: .personal,
            tags: ["daily-routine"],
            userId: "user-1"
        )
        task.semanticProfile = TaskSemanticProfile(semanticType: .generic, subtype: "misc")
        XCTAssertEqual(LifeTimelineKindResolver.kind(for: task), .habit)
    }

    func testBreakfastMapsToHealthNotShopping() {
        let task = LifeTask(
            title: "Breakfast",
            lifeArea: .health,
            tags: ["daily-routine"],
            recurrence: .daily,
            userId: "user-1"
        )
        XCTAssertEqual(LifeTimelineKindResolver.kind(for: task), .health)
    }

    func testSleepBoundaryStaysRecovery() {
        let task = LifeTask(title: "Wind down · Sleep", lifeArea: .health, userId: "user-1")
        XCTAssertEqual(LifeTimelineKindResolver.kind(for: task), .health)
    }
}
