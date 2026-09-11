import XCTest
@testable import LookAfterCore

final class RoutineScheduleAnchorResolverTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testDinnerAnchorIsEveningNotMidday() throws {
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 7)))
        var dinner = LifeTask(
            title: "Dinner",
            lifeArea: .health,
            estimatedMinutes: 45,
            scheduledDate: day,
            scheduledTime: calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day),
            tags: ["daily-routine", "fixed"],
            schedulingMode: .flexible,
            userId: "user-1"
        )
        dinner = TaskEphemeralityDefaults.enrich(dinner)

        let anchor = try XCTUnwrap(
            RoutineScheduleAnchorResolver.resolve(for: dinner, on: day, calendar: calendar)
        )
        XCTAssertEqual(calendar.component(.hour, from: anchor.start), 19)
        XCTAssertFalse(anchor.treatAsFixed)
        XCTAssertTrue(RoutineScheduleAnchorResolver.shouldRestore(task: dinner, anchor: anchor, calendar: calendar))
    }

    func testGymDateOnlyGetsSixPMAnchor() throws {
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 7)))
        var gym = LifeTask(
            title: "Gym",
            lifeArea: .health,
            estimatedMinutes: 60,
            scheduledDate: day,
            userId: "user-1"
        )
        gym = TaskEphemeralityDefaults.enrich(gym)

        let anchor = try XCTUnwrap(
            RoutineScheduleAnchorResolver.resolve(for: gym, on: day, calendar: calendar)
        )
        XCTAssertEqual(calendar.component(.hour, from: anchor.start), 18)
        XCTAssertTrue(anchor.treatAsFixed)
    }

    func testGymUsesLifeModelEveningBlockOverSeederDefault() throws {
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 7)))
        let gymBlock = ProtectedTimeBlock(
            label: "Gym",
            days: .weekdays,
            startHour: 18,
            startMinute: 30,
            endHour: 19,
            endMinute: 30,
            protection: .neverSchedule
        )
        let model = LifeModel(
            identity: LifeIdentity(name: "Sam", roleFraming: "", mission: "", longTermVision: ""),
            timeBlocks: [gymBlock],
            commitments: [
                LifeCommitment(
                    title: "Gym",
                    lifeArea: .health,
                    frequency: .weekdays,
                    preferredBlockLabel: "Gym",
                    defaultMinutes: 60,
                    isNonNegotiable: true
                )
            ]
        )
        var gym = LifeTask(
            title: "Gym",
            lifeArea: .health,
            estimatedMinutes: 60,
            scheduledDate: day,
            scheduledTime: calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day),
            tags: [LifeModel.commitmentTaskTag],
            userId: "user-1"
        )
        gym = TaskEphemeralityDefaults.enrich(gym)

        let anchor = try XCTUnwrap(
            RoutineScheduleAnchorResolver.resolve(for: gym, on: day, model: model, calendar: calendar)
        )
        XCTAssertEqual(calendar.component(.hour, from: anchor.start), 18)
        XCTAssertEqual(calendar.component(.minute, from: anchor.start), 30)
        XCTAssertTrue(anchor.treatAsFixed)
        XCTAssertTrue(RoutineScheduleAnchorResolver.shouldRestore(task: gym, anchor: anchor, calendar: calendar))
    }

    func testCommutePreferredBeforeOfficeWork() throws {
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 7)))
        var profile = UserLifeProfile()
        profile.workStartHour = 9
        profile.workEndHour = 17

        let commute = LifeTask(
            title: "Commute & Reset",
            lifeArea: .personal,
            estimatedMinutes: 60,
            userId: "user-1"
        )
        let office = LifeTask(
            title: "Office Work",
            lifeArea: .work,
            estimatedMinutes: 60,
            userId: "user-1"
        )

        let commuteStart = try XCTUnwrap(
            RoutineScheduleAnchorResolver.preferredStart(
                for: commute,
                on: day,
                profile: profile,
                calendar: calendar
            )
        )
        let officeStart = try XCTUnwrap(
            RoutineScheduleAnchorResolver.preferredStart(
                for: office,
                on: day,
                profile: profile,
                calendar: calendar
            )
        )

        XCTAssertLessThan(commuteStart, officeStart)
        XCTAssertEqual(calendar.component(.hour, from: officeStart), 9)
    }

    func testFixedNoteAnchorForStandup() throws {
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 7)))
        var profile = UserLifeProfile()
        profile.fixedScheduleNotes = "Daily Stand-up 2:35 PM"

        let standup = LifeTask(
            title: "Daily Stand-up",
            lifeArea: .work,
            estimatedMinutes: 30,
            userId: "user-1"
        )

        let anchor = try XCTUnwrap(
            RoutineScheduleAnchorResolver.resolve(
                for: standup,
                on: day,
                profile: profile,
                calendar: calendar
            )
        )
        XCTAssertEqual(calendar.component(.hour, from: anchor.start), 14)
        XCTAssertEqual(calendar.component(.minute, from: anchor.start), 35)
        XCTAssertTrue(anchor.treatAsFixed)
    }
}
