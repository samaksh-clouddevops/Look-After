import XCTest
@testable import LifeOSCore

final class LifeModelValidatorTests: XCTestCase {

    private var fixtureMarkdown: String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("LifeOS-iOS/Resources/example-life-profile.md")
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
            completedTasks: [],
            activeTasks: [],
            now: weekday,
            lookbackDays: 7
        )

        XCTAssertFalse(gaps.isEmpty)
        XCTAssertTrue(gaps.contains { $0.commitmentTitle == "Gym" || $0.commitmentTitle.lowercased().contains("creative") })
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
