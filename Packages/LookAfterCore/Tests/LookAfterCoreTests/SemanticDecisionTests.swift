import XCTest
@testable import LookAfterCore

final class SemanticDecisionTests: XCTestCase {

    func testHealthKitTaskRendersWithoutAwkwardFinishStart() {
        let task = LifeTask(title: "HealthKit Integration", estimatedMinutes: 18)
        let semantics = SemanticDecisionBuilder.from(task: task)
        let rendered = HumanLanguage.render(semantics)

        XCTAssertEqual(rendered.headline, "Finish connecting Apple Health")
        XCTAssertFalse(rendered.headline.lowercased().contains("finish start"))
        XCTAssertTrue(rendered.benefitLine.contains("sleep") || rendered.benefitLine.contains("health"))
        XCTAssertTrue(rendered.durationLine.contains("18"))
    }

    func testStartWorkPreservesTitle() {
        XCTAssertEqual(HumanLanguage.outcomeHeadline(title: "Start Work"), "Start Work")
        XCTAssertEqual(HumanLanguage.outcomeHeadline(title: "Start Work", progress: 0.4), "Continue Working")
    }

    func testSemanticPipelineIsDeterministic() {
        let task = LifeTask(title: "Implement OAuth sign-in", estimatedMinutes: 25)
        let first = HumanLanguage.render(SemanticDecisionBuilder.from(task: task))
        let second = HumanLanguage.render(SemanticDecisionBuilder.from(task: task))
        XCTAssertEqual(first, second)
    }

    func testRecommendationSummaryJoinsThreeLines() {
        let task = LifeTask(title: "Apple Health sync", estimatedMinutes: 18)
        let summary = HumanLanguage.recommendationSummary(from: SemanticDecisionBuilder.from(task: task))
        let lines = summary.components(separatedBy: "\n")
        XCTAssertGreaterThanOrEqual(lines.count, 2)
    }
}
