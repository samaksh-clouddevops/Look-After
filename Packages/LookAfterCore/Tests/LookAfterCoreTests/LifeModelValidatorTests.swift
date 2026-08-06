import XCTest
@testable import LookAfterCore

final class LifeModelValidatorTests: XCTestCase {

    private var fixtureMarkdown: String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Apps/LookAfter-iOS/Resources/example-life-profile.md")
        if let text = try? String(contentsOf: url), !text.isEmpty {
            return text
        }
        return Self.inlineFixture
    }

    func testLocalCompileExtractsWorkGymAndCreativeBlocks() {
        let model = LifeModelValidator.compileLocally(from: fixtureMarkdown)

        XCTAssertFalse(model.identity.name.isEmpty)
        XCTAssertTrue(model.identity.name.contains("Alex") || model.identity.mission.lowercased().contains("habit"))

        let office = model.timeBlocks.first { block in
            let label = block.label.lowercased()
            return label.contains("office") || label.contains("work")
        }
        XCTAssertNotNil(office)

        let gym = model.timeBlocks.first { $0.label.lowercased().contains("gym") }
        XCTAssertNotNil(gym)
        XCTAssertEqual(gym?.protection, .neverSchedule)

        let creative = model.timeBlocks.first { $0.label.lowercased().contains("creative") || $0.label.lowercased().contains("side project") }
        XCTAssertNotNil(creative)

        XCTAssertTrue(model.commitments.contains { $0.title == "Gym" })
    }

    func testLifeGapDetectorFlagsMissingCommitments() {
        let model = LifeModelValidator.compileLocally(from: fixtureMarkdown)
        let weekday = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 4))!
        let gaps = LifeGapDetector.detect(
            model: model,
            allTasks: [],
            now: weekday,
            lookbackDays: 7
        )

        XCTAssertFalse(gaps.isEmpty)
        XCTAssertTrue(gaps.contains { $0.commitmentTitle == "Gym" || $0.commitmentTitle.lowercased().contains("creative") })
        XCTAssertTrue(gaps.contains { $0.message.contains("Not logged recently") })
    }

    func testLifeGapDetectorSkipsRecentlyCompletedCommitment() {
        let model = LifeModelValidator.compileLocally(from: fixtureMarkdown)
        let today = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 4, hour: 18))!
        var gym = LifeTask(
            title: "Gym",
            lifeArea: .health,
            status: .completed,
            tags: [LifeModel.commitmentTaskTag, model.commitmentID(for: "Gym")],
            userId: "user-1"
        )
        gym.completedAt = today

        let gaps = LifeGapDetector.detect(
            model: model,
            allTasks: [gym],
            now: today
        )

        XCTAssertFalse(gaps.contains { $0.commitmentTitle == "Gym" })
    }

    func testLifeGapDetectorRecognizesInformalCompletionTitles() {
        let model = LifeModelValidator.compileLocally(from: fixtureMarkdown)
        let today = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 4, hour: 18))!
        var gym = LifeTask(
            title: "Gym workout",
            lifeArea: .health,
            status: .completed,
            userId: "user-1"
        )
        gym.completedAt = today

        let gaps = LifeGapDetector.detect(
            model: model,
            allTasks: [gym],
            now: today
        )

        XCTAssertFalse(gaps.contains { $0.commitmentTitle == "Gym" })
    }

    func testLifeGapDetectorStillFlagsScheduledButIncompleteCommitment() {
        let model = LifeModelValidator.compileLocally(from: fixtureMarkdown)
        let today = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 4, hour: 18))!
        let day = Calendar.current.startOfDay(for: today)
        let gym = LifeTask(
            title: "Gym",
            lifeArea: .health,
            scheduledDate: day,
            tags: [LifeModel.commitmentTaskTag, model.commitmentID(for: "Gym")],
            userId: "user-1"
        )

        let gaps = LifeGapDetector.detect(
            model: model,
            allTasks: [gym],
            now: today
        )

        XCTAssertTrue(gaps.contains { $0.commitmentTitle == "Gym" })
    }

    func testLifeGapDetectorMatchesMusicProductionByKeyword() {
        let model = LifeModelValidator.compileLocally(from: fixtureMarkdown)
        let today = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 4, hour: 21))!
        var music = LifeTask(
            title: "Music production session",
            lifeArea: .creativity,
            status: .completed,
            userId: "user-1"
        )
        music.completedAt = today

        let gaps = LifeGapDetector.detect(
            model: model,
            allTasks: [music],
            now: today
        )

        XCTAssertTrue(gaps.filter { $0.commitmentTitle.lowercased().contains("creative") || $0.commitmentTitle.lowercased().contains("music") }.isEmpty)
    }

    func testLifeGapDetectorSkipsWhenCompletedAtComesFromUpdatedAt() {
        let model = LifeModelValidator.compileLocally(from: fixtureMarkdown)
        let today = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 4, hour: 19))!
        var gym = LifeTask(
            title: "Gym",
            lifeArea: .health,
            status: .completed,
            tags: [LifeModel.commitmentTaskTag, model.commitmentID(for: "Gym")],
            userId: "user-1"
        )
        gym.updatedAt = today

        let gaps = LifeGapDetector.detect(
            model: model,
            allTasks: [gym],
            now: today
        )

        XCTAssertFalse(gaps.contains { $0.commitmentTitle == "Gym" })
    }

    private static let inlineFixture = """
    # My Core Identity
    My name is **Alex Chen**.
    I work as a product designer and want to build a healthier daily rhythm.

    # My Mission
    Build sustainable habits around work, health, and creative time.

    # Fixed Schedule
    ### Gym
    **6:00 PM – 7:00 PM**

    ### Creative / side project
    **8:00 PM – 9:30 PM**
    Priority order:
    1. Side project work
    2. Writing
    """
}
