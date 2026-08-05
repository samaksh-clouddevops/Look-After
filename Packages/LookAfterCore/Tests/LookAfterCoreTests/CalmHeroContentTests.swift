import XCTest
@testable import LookAfterCore

final class CalmHeroContentTests: XCTestCase {

    func testVisibleSurfaceUsesSingleSupportingLine() {
        let content = CalmHeroContentBuilder.fromBriefingHero(
            .init(
                greeting: "Good evening, Alex",
                actionLine: "Review Azure deployment",
                narrative: "You've already finished the hardest part of today. Before dinner, pay your electricity bill—it'll take about three minutes.",
                whyLine: "You still have 45 minutes before dinner.",
                buttonLabel: "Start now",
                durationLabel: "About 30 minutes",
                ignoreConsequence: "Tomorrow gets busier if you skip this.",
                alternativeLabel: nil
            )
        )

        XCTAssertEqual(content.title, "Review Azure deployment")
        XCTAssertEqual(content.supportingLine, "You still have 45 minutes before dinner.")
        XCTAssertTrue(content.metadataLine?.contains("Good evening") == true)
        XCTAssertTrue(content.disclosure?.narrative?.contains("electricity bill") == true)
    }

    func testMetadataCombinesGreetingAndDuration() {
        let metadata = CalmHeroContentBuilder.metadataLine(
            greeting: "Good evening",
            duration: "About 20 minutes",
            window: "5:00 PM – 6:00 PM"
        )
        XCTAssertEqual(metadata, "Good evening · About 20 minutes · 5:00 PM – 6:00 PM")
    }

    func testFirstSentenceTruncatesLongText() {
        let long = String(repeating: "word ", count: 30)
        let line = CalmHeroContentBuilder.firstSentence(long)
        XCTAssertLessThanOrEqual(line.count, 90)
    }
}
