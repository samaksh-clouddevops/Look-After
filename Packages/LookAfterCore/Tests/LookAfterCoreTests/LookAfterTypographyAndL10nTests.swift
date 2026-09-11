import XCTest
@testable import LookAfterCore
import SwiftUI

final class LookAfterTypographyTests: XCTestCase {
    func testTextRolesMapToSystemStyles() {
        XCTAssertEqual(LookAfterTypography.TextRole.body.textStyle, .body)
        XCTAssertEqual(LookAfterTypography.TextRole.caption.textStyle, .caption2)
        XCTAssertEqual(LookAfterTypography.TextRole.screenTitle.textStyle, .title)
        XCTAssertEqual(LookAfterTypography.TextRole.briefingUserName.textStyle, .title2)
    }

    func testDefaultPointSizesPreserved() {
        XCTAssertEqual(LookAfterTypography.TextRole.body.pointSize, 14)
        XCTAssertEqual(LookAfterTypography.TextRole.briefingUserName.pointSize, 30)
        XCTAssertEqual(LookAfterTypography.TextRole.tabLabel.pointSize, 11)
    }
}

final class LookAfterL10nTests: XCTestCase {
    func testEnglishChromeStrings() {
        XCTAssertEqual(LookAfterL10n.tabBriefing, "Briefing")
        XCTAssertEqual(LookAfterL10n.tabCapture, "Capture")
        XCTAssertEqual(LookAfterL10n.widgetNow, "NOW")
        XCTAssertEqual(LookAfterL10n.widgetDoneToday(count: 2), "2 done today")
    }
}
