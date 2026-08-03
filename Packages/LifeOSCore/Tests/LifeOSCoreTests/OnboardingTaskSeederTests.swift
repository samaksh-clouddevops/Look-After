import XCTest
@testable import LifeOSCore

final class OnboardingTaskSeederTests: XCTestCase {

    func testCreatesFixedTasksFromScheduleNotes() {
        var profile = UserLifeProfile()
        profile.fixedScheduleNotes = "Daily standup 10:00 AM; Gym 7 PM"

        let seed = OnboardingTaskSeeder.seedTasks(from: profile)

        XCTAssertGreaterThanOrEqual(seed.fixedTasks.count, 2)
        XCTAssertTrue(seed.fixedTasks.allSatisfy(\.isFixedTimeEvent))
        XCTAssertTrue(seed.fixedTasks.contains { $0.title == "Daily standup" })
        XCTAssertTrue(seed.fixedTasks.contains { $0.title == "Gym" })
    }

    func testDoesNotCreateTasksFromMeetingProse() {
        var profile = UserLifeProfile()
        profile.profileText = """
        PERSONALITY & WORK STYLE
        I am a PM with many meetings during the day.
        HOW THE AI SHOULD PLAN
        No meetings after 4 PM — mornings for deep work.
        """

        let seed = OnboardingTaskSeeder.seedTasks(from: profile)

        XCTAssertFalse(seed.fixedTasks.contains { $0.title.lowercased().contains("meeting") && $0.title.count > 20 })
        XCTAssertFalse(seed.allTasks.contains { $0.title.lowercased().contains("planner") })
    }

    func testCreatesFlexibleMedicationTaskFromProfileText() {
        var profile = UserLifeProfile()
        profile.profileText = "I take medication every morning before work."

        let seed = OnboardingTaskSeeder.seedTasks(from: profile)

        XCTAssertTrue(seed.flexibleTasks.contains { $0.title == "Take medication" })
    }

    func testFallbackIncludesDailyRoutinesWhenNothingParsed() {
        let seed = OnboardingTaskSeeder.seedTasks(from: UserLifeProfile())
        XCTAssertTrue(seed.fixedTasks.contains { $0.title == "Breakfast" })
        XCTAssertTrue(seed.fixedTasks.contains { $0.title == "Dinner" })
        XCTAssertTrue(seed.flexibleTasks.contains { $0.title == "Take medication" })
        XCTAssertTrue(seed.flexibleTasks.contains { $0.title == "Morning review" })
        XCTAssertFalse(seed.flexibleTasks.contains { $0.title == "Journal" })
    }

    func testDetectsJunkTitles() {
        XCTAssertTrue(OnboardingTaskSeeder.isJunkOnboardingTask(
            title: "Finish your life profile fixed time never moved by the planner"
        ))
        XCTAssertTrue(OnboardingTaskSeeder.isJunkOnboardingTask(title: "8:30 AM –"))
        XCTAssertTrue(OnboardingTaskSeeder.isJunkOnboardingTask(title: "Protect office hours (– 5:30 PM)"))
        XCTAssertTrue(OnboardingTaskSeeder.isJunkOnboardingTask(title: "– Daily stand-up/ work meeting"))
        XCTAssertFalse(OnboardingTaskSeeder.isJunkOnboardingTask(title: "Meeting"))
        XCTAssertFalse(OnboardingTaskSeeder.isJunkOnboardingTask(title: "Daily standup"))
    }

    func testParsesTimeFirstScheduleNotes() {
        var profile = UserLifeProfile()
        profile.fixedScheduleNotes = "8:30 AM – Daily stand-up/ work meeting"

        let seed = OnboardingTaskSeeder.seedTasks(from: profile)

        XCTAssertTrue(seed.fixedTasks.contains { $0.title == "Daily stand-up work meeting" })
    }

    func testDoesNotRescanProfileWhenFixedNotesExist() {
        var profile = UserLifeProfile()
        profile.fixedScheduleNotes = "Daily standup 10:00 AM"
        profile.profileText = "I have many meetings during the day at 2 PM and 3 PM."

        let seed = OnboardingTaskSeeder.seedTasks(from: profile)

        XCTAssertTrue(seed.fixedTasks.contains { $0.title == "Daily standup" })
        XCTAssertFalse(seed.fixedTasks.contains { $0.title.lowercased().contains("meeting") && $0.title.count > 25 })
    }

    func testRejectsOfficeHoursBoundaryNotes() {
        var profile = UserLifeProfile()
        profile.fixedScheduleNotes = "Protect office hours (– 5:30 PM); 8:30 AM –"

        let seed = OnboardingTaskSeeder.seedTasks(from: profile)

        XCTAssertFalse(seed.fixedTasks.contains { $0.title.lowercased().contains("office hours") })
        XCTAssertTrue(seed.flexibleTasks.contains { $0.title == "Take medication" })
    }

    func testMergesExtractedScheduleWhenFixedNotesExist() {
        var profile = UserLifeProfile()
        profile.fixedScheduleNotes = "Protect office hours (– 5:30 PM)"
        profile.profileText = "Daily stand-up at 8:30 AM each weekday."

        let seed = OnboardingTaskSeeder.seedTasks(from: profile)

        XCTAssertTrue(seed.fixedTasks.contains { $0.title == "Daily standup" })
    }
}
