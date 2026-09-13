import XCTest
@testable import LookAfterCore

final class RoutineBlockTests: XCTestCase {

    override func tearDown() {
        RoutineBlockStore.reset()
        super.tearDown()
    }

    // MARK: - Overlap validation

    func testOverlapDetectsSameDaySharedRange() {
        let gym = RoutineBlock(title: "Gym", days: .everyDay, startHour: 6, startMinute: 0, durationMinutes: 60)
        let breakfast = RoutineBlock(title: "Breakfast", days: .everyDay, startHour: 6, startMinute: 30, durationMinutes: 30)
        XCTAssertTrue(gym.overlaps(breakfast))
        XCTAssertTrue(breakfast.overlaps(gym))
    }

    func testOverlapFalseWhenAdjacentNotOverlapping() {
        let gym = RoutineBlock(title: "Gym", days: .everyDay, startHour: 6, startMinute: 0, durationMinutes: 60)
        let breakfast = RoutineBlock(title: "Breakfast", days: .everyDay, startHour: 7, startMinute: 0, durationMinutes: 30)
        XCTAssertFalse(gym.overlaps(breakfast))
    }

    func testOvernightSleepOverlapsMorningGym() {
        let sleep = RoutineBlock(title: "Sleep", days: .everyDay, startHour: 23, startMinute: 0, durationMinutes: 480)
        let gym = RoutineBlock(title: "Gym", days: .everyDay, startHour: 6, startMinute: 0, durationMinutes: 60)
        XCTAssertTrue(sleep.overlaps(gym))
        XCTAssertTrue(gym.overlaps(sleep))
    }

    func testOvernightSleepDoesNotOverlapAfternoon() {
        let sleep = RoutineBlock(title: "Sleep", days: .everyDay, startHour: 23, startMinute: 0, durationMinutes: 480)
        let lunch = RoutineBlock(title: "Lunch", days: .everyDay, startHour: 13, startMinute: 0, durationMinutes: 45)
        XCTAssertFalse(sleep.overlaps(lunch))
    }

    func testOverlapFalseWhenNoSharedDay() {
        let weekdayGym = RoutineBlock(title: "Gym", days: .weekdays, startHour: 6, startMinute: 0, durationMinutes: 60)
        let weekendGym = RoutineBlock(title: "Long run", days: .weekends, startHour: 6, startMinute: 0, durationMinutes: 60)
        XCTAssertFalse(weekdayGym.overlaps(weekendGym))
    }

    func testConflictsExcludesSelfByID() {
        let block = RoutineBlock(title: "Gym", days: .everyDay, startHour: 6, startMinute: 0, durationMinutes: 60)
        RoutineBlockStore.save([block])
        let conflicts = RoutineBlockStore.conflicts(with: block)
        XCTAssertTrue(conflicts.isEmpty)
    }

    func testConflictsFindsOverlapAgainstStore() {
        let existing = RoutineBlock(title: "Gym", days: .everyDay, startHour: 6, startMinute: 0, durationMinutes: 60)
        RoutineBlockStore.save([existing])
        let candidate = RoutineBlock(title: "Meditation", days: .everyDay, startHour: 6, startMinute: 30, durationMinutes: 15)
        let conflicts = RoutineBlockStore.conflicts(with: candidate)
        XCTAssertEqual(conflicts.map(\.title), ["Gym"])
    }

    // MARK: - Migration from fixedScheduleNotes

    func testImportFromFixedScheduleNotesParsesEntries() {
        let notes = "Gym 6am-7am, Lunch 1pm"
        let imported = RoutineBlockStore.importFromFixedScheduleNotes(notes)
        XCTAssertFalse(imported.isEmpty, "Expected at least one parsed routine block from notes")
        XCTAssertTrue(imported.allSatisfy { $0.isNonNegotiable })
        if let gym = imported.first(where: { $0.title.localizedCaseInsensitiveContains("Gym") }) {
            XCTAssertEqual(gym.title, "Gym")
            XCTAssertFalse(gym.title.contains("am"))
        }
    }

    func testTitleFromFixedNotePreservesNonTimeText() {
        XCTAssertEqual(RoutineBlockStore.titleFromFixedNote("Gym 6am-7am"), "Gym")
        XCTAssertEqual(RoutineBlockStore.titleFromFixedNote("Deep Work 9am"), "Deep Work")
    }

    func testImportFromFixedScheduleNotesEmptyReturnsEmpty() {
        XCTAssertTrue(RoutineBlockStore.importFromFixedScheduleNotes("").isEmpty)
        XCTAssertTrue(RoutineBlockStore.importFromFixedScheduleNotes("   ").isEmpty)
    }

    func testMigrateFixedScheduleNotesSkipsOverlapsWithExisting() {
        let existing = RoutineBlock(title: "Gym", days: .everyDay, startHour: 6, startMinute: 0, durationMinutes: 60)
        RoutineBlockStore.save([existing])
        // Same time window as existing "Gym" block should be skipped as a conflict.
        let added = RoutineBlockStore.migrateFixedScheduleNotesIfNeeded("Gym 6am-7am")
        XCTAssertTrue(added.isEmpty)
        XCTAssertEqual(RoutineBlockStore.load().count, 1)
    }

    // MARK: - DayStructureCompiler anchor merge

    func testDayStructureCompilerIncludesActiveRoutineBlockAnchor() {
        let block = RoutineBlock(title: "Deep Work", days: .everyDay, startHour: 9, startMinute: 0, durationMinutes: 90, isNonNegotiable: true)
        RoutineBlockStore.save([block])

        let structure = DayStructureCompiler.compile(profile: UserLifeProfile(), model: nil)
        let anchor = structure.anchors.first { $0.id == "routine-block.\(block.id)" }
        XCTAssertNotNil(anchor)
        XCTAssertEqual(anchor?.startHour, 9)
        XCTAssertEqual(anchor?.durationMinutes, 90)
        XCTAssertEqual(anchor?.treatAsFixed, true)
    }

    func testDayStructureCompilerExcludesRoutineBlockOnNonMatchingDay() {
        // Weekend-only block should not appear when compiling for a day it doesn't cover,
        // unless today happens to be a weekend — so instead verify a block scoped to no days is excluded.
        var noDays = WeekdaySet.everyDay
        noDays.monday = false; noDays.tuesday = false; noDays.wednesday = false
        noDays.thursday = false; noDays.friday = false; noDays.saturday = false; noDays.sunday = false
        let block = RoutineBlock(title: "Never", days: noDays, startHour: 10, startMinute: 0, durationMinutes: 30)
        RoutineBlockStore.save([block])

        let structure = DayStructureCompiler.compile(profile: UserLifeProfile(), model: nil)
        XCTAssertNil(structure.anchors.first { $0.id == "routine-block.\(block.id)" })
    }

    func testDayStructureCompilerDeduplicatesByAnchorID() {
        let block = RoutineBlock(title: "Deep Work", days: .everyDay, startHour: 9, startMinute: 0, durationMinutes: 90)
        RoutineBlockStore.save([block, block])

        let structure = DayStructureCompiler.compile(profile: UserLifeProfile(), model: nil)
        let matches = structure.anchors.filter { $0.id == "routine-block.\(block.id)" }
        XCTAssertEqual(matches.count, 1)
    }
}
