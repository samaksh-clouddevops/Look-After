import XCTest
@testable import LookAfterFeatures
import LookAfterCore

final class TimelinePreviewWindowTests: XCTestCase {
    func testCenteredWindowKeepsCompletedAroundNow() {
        let now = Date()
        let rows: [ExecutivePlanningTimelineRow] = (0..<9).map { index in
            ExecutivePlanningTimelineRow(
                id: "r\(index)",
                sortDate: now.addingTimeInterval(TimeInterval((index - 4) * 1800)),
                timeLabel: "\(index)",
                title: "Task \(index)",
                isNow: index == 4,
                isCompleted: index < 4,
                taskId: "t\(index)"
            )
        }

        let window = TimelinePreviewWindow.centered(rows: rows, now: now)
        XCTAssertEqual(window.count, 5)
        XCTAssertEqual(window.map(\.id), ["r2", "r3", "r4", "r5", "r6"])
        XCTAssertTrue(window.contains(where: \.isCompleted))
        XCTAssertTrue(window.contains(where: \.isNow))
    }

    func testOverdueDetectorRequiresTwoHourGrace() {
        let now = Date()
        let overdue = ExecutivePlanningTimelineRow(
            id: "old",
            sortDate: now.addingTimeInterval(-4 * 3600),
            timeLabel: "10:00",
            title: "Late lunch",
            isCompleted: false,
            estimatedMinutes: 30,
            taskId: "late-1"
        )
        let recent = ExecutivePlanningTimelineRow(
            id: "fresh",
            sortDate: now.addingTimeInterval(-30 * 60),
            timeLabel: "Now",
            title: "Recent",
            isCompleted: false,
            estimatedMinutes: 20,
            taskId: "fresh-1"
        )

        let found = OverdueTimelineDetector.overdueTaskRows(from: [overdue, recent], now: now)
        XCTAssertEqual(found.map(\.id), ["old"])
    }
}
