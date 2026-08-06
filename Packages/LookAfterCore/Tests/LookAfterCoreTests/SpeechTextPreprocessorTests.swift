import XCTest
@testable import LookAfterCore

final class SpeechTextPreprocessorTests: XCTestCase {

    func testStripsMarkdownFormatting() {
        let input = """
        ## Plan
        **Focus** on the *deck* and `API` task.
        > Stay calm
        """
        let out = SpeechTextPreprocessor.prepareForSpeech(input)
        XCTAssertFalse(out.contains("**"))
        XCTAssertFalse(out.contains("*"))
        XCTAssertFalse(out.contains("`"))
        XCTAssertFalse(out.contains("#"))
        XCTAssertFalse(out.contains(">"))
        XCTAssertTrue(out.localizedCaseInsensitiveContains("Focus"))
        XCTAssertTrue(out.localizedCaseInsensitiveContains("deck"))
        XCTAssertTrue(out.localizedCaseInsensitiveContains("API") || out.localizedCaseInsensitiveContains("A.I."))
    }

    func testNormalizesBulletListToProse() {
        let input = """
        Here's the plan:
        - Open the deck
        - Tighten the narrative
        - Send to Sam
        """
        let out = SpeechTextPreprocessor.prepareForSpeech(input)
        XCTAssertFalse(out.contains("- "))
        XCTAssertTrue(out.localizedCaseInsensitiveContains("Open the deck"))
        XCTAssertTrue(out.localizedCaseInsensitiveContains("and"))
        XCTAssertTrue(out.localizedCaseInsensitiveContains("Send to Sam"))
    }

    func testNormalizesNumberedList() {
        let input = """
        1. Start the timer
        2. Work for 25 min
        3. Take a break
        """
        let out = SpeechTextPreprocessor.prepareForSpeech(input)
        XCTAssertFalse(out.contains("1."))
        XCTAssertTrue(out.localizedCaseInsensitiveContains("minutes"))
        XCTAssertTrue(out.localizedCaseInsensitiveContains("Start the timer"))
    }

    func testExpandsAbbreviations() {
        let input = "Block ~45 min for deep work, approx. 2 hrs total. OK to use PPL today."
        let out = SpeechTextPreprocessor.prepareForSpeech(input)
        XCTAssertTrue(out.localizedCaseInsensitiveContains("minutes"))
        XCTAssertTrue(out.localizedCaseInsensitiveContains("approximately"))
        XCTAssertTrue(out.localizedCaseInsensitiveContains("hours"))
        XCTAssertTrue(out.localizedCaseInsensitiveContains("okay"))
        XCTAssertTrue(out.contains("Push-Pull-Legs"))
    }

    func testStripsCodeFences() {
        let input = """
        Done.
        ```json
        {"a":1}
        ```
        Next step is stretch.
        """
        let out = SpeechTextPreprocessor.prepareForSpeech(input)
        XCTAssertFalse(out.contains("```"))
        XCTAssertFalse(out.contains("\"a\""))
        XCTAssertTrue(out.localizedCaseInsensitiveContains("Next step is stretch"))
    }

    func testLinksBecomeLabels() {
        let input = "See the [briefing](https://example.com/x) for details."
        let out = SpeechTextPreprocessor.prepareForSpeech(input)
        XCTAssertTrue(out.contains("briefing"))
        XCTAssertFalse(out.contains("https://"))
    }

    func testEmptyInput() {
        XCTAssertEqual(SpeechTextPreprocessor.prepareForSpeech("   "), "")
    }
}
