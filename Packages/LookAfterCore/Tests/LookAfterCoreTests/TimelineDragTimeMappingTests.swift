import XCTest
@testable import LookAfterCore

final class TimelineDragTimeMappingTests: XCTestCase {

    func testOffsetMinutesSnapsToFifteenMinuteGrid() {
        XCTAssertEqual(TimelineDragTimeMapping.offsetMinutes(from: 0), 0)
        XCTAssertEqual(TimelineDragTimeMapping.offsetMinutes(from: 48), 15)
        XCTAssertEqual(TimelineDragTimeMapping.offsetMinutes(from: 96), 30)
        XCTAssertEqual(TimelineDragTimeMapping.offsetMinutes(from: -48), -15)
    }

    func testProposedStartAppliesSnappedDelta() {
        let calendar = Calendar.current
        let baseline = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!
        let proposed = TimelineDragTimeMapping.proposedStart(
            baseline: baseline,
            verticalOffset: 96,
            calendar: calendar
        )
        let delta = calendar.dateComponents([.minute], from: baseline, to: proposed).minute
        XCTAssertEqual(delta, 30)
    }
}
