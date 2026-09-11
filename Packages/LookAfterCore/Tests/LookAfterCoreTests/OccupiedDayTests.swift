import XCTest
@testable import LookAfterCore

final class OccupiedDayTests: XCTestCase {
    func testCalendarMeetingOccupiesAndOverlapsFlexTask() {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10))!
        let meetingStart = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
        let meetingEnd = calendar.date(bySettingHour: 13, minute: 0, second: 0, of: day)!
        let events = [
            BriefingCalendarEvent(
                id: "meet-1",
                title: "Standup",
                startDate: meetingStart,
                timeLabel: "12:00 PM",
                endDate: meetingEnd
            )
        ]
        let flex = LifeTask(
            id: "flex-1",
            title: "Deep work",
            estimatedMinutes: 45,
            scheduledDate: day,
            scheduledTime: meetingStart,
            userId: "u1"
        )

        let occupied = OccupiedDay.build(
            tasks: [flex],
            calendarEvents: events,
            model: nil,
            on: day,
            calendar: calendar
        )
        XCTAssertTrue(occupied.hasOverlap)
        XCTAssertTrue(occupied.fixedIntervals.contains(where: { $0.taskID.hasPrefix("cal.") }))
    }

    func testFreeAllDayDoesNotOccupy() {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10))!
        let events = [
            BriefingCalendarEvent(
                id: "holiday",
                title: "Holiday",
                startDate: day,
                timeLabel: "All day",
                endDate: calendar.date(byAdding: .day, value: 1, to: day),
                isAllDay: true,
                isBusy: false
            )
        ]
        let occupied = OccupiedDay.build(
            tasks: [],
            calendarEvents: events,
            model: nil,
            on: day,
            calendar: calendar
        )
        XCTAssertTrue(occupied.fixedIntervals.filter { $0.taskID.hasPrefix("cal.") }.isEmpty)
    }

    func testBusyAllDayOccupies() {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10))!
        let events = [
            BriefingCalendarEvent(
                id: "ooo",
                title: "OOO",
                startDate: day,
                timeLabel: "All day",
                endDate: calendar.date(byAdding: .day, value: 1, to: day),
                isAllDay: true,
                isBusy: true
            )
        ]
        let occupied = OccupiedDay.build(
            tasks: [],
            calendarEvents: events,
            model: nil,
            on: day,
            calendar: calendar
        )
        XCTAssertFalse(occupied.fixedIntervals.filter { $0.taskID.hasPrefix("cal.") }.isEmpty)
    }

    func testGuardRejectsDropOntoCalendar() {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10))!
        let meetingStart = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
        let meetingEnd = calendar.date(bySettingHour: 13, minute: 0, second: 0, of: day)!
        let events = [
            BriefingCalendarEvent(
                id: "meet-1",
                title: "Standup",
                startDate: meetingStart,
                timeLabel: "12:00 PM",
                endDate: meetingEnd
            )
        ]
        var flex = LifeTask(
            id: "flex-1",
            title: "Deep work",
            estimatedMinutes: 30,
            scheduledDate: day,
            userId: "u1"
        )
        flex.applyTimeConstraint(.flexible)

        let occupied = OccupiedDay.build(
            tasks: [],
            calendarEvents: events,
            model: nil,
            on: day,
            calendar: calendar
        ).occupiedForPlacement()

        let placement = SchedulePlacementGuard.evaluate(
            proposedStart: meetingStart,
            durationMinutes: 30,
            task: flex,
            occupied: occupied,
            calendar: calendar,
            mode: .rejectOutsideBox
        )
        switch placement {
        case .accepted(let date), .snapped(let date):
            XCTAssertGreaterThanOrEqual(date, meetingEnd)
        case .rejected, .needsAI:
            break
        }
    }

    func testCascadeShiftsFlexOffCalendar() {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10))!
        let meetingStart = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
        let meetingEnd = calendar.date(bySettingHour: 13, minute: 0, second: 0, of: day)!
        let events = [
            BriefingCalendarEvent(
                id: "meet-1",
                title: "Standup",
                startDate: meetingStart,
                timeLabel: "12:00 PM",
                endDate: meetingEnd
            )
        ]
        var flex = LifeTask(
            id: "flex-1",
            title: "Deep work",
            estimatedMinutes: 30,
            scheduledDate: day,
            scheduledTime: meetingStart,
            userId: "u1"
        )
        flex.applyTimeConstraint(.flexible)

        let result = ConflictResolutionCascade.resolve(
            tasks: [flex],
            on: day,
            calendar: calendar,
            calendarEvents: events
        )
        let updated = result.tasks.first { $0.id == "flex-1" }
        XCTAssertNotNil(updated?.scheduledTime)
        if let start = updated?.scheduledTime {
            XCTAssertGreaterThanOrEqual(start, meetingEnd.addingTimeInterval(-1))
        }
        XCTAssertFalse(
            DayScheduleReconciler.hasOverlap(
                result.tasks,
                on: day,
                calendar: calendar,
                calendarEvents: events
            )
        )
    }
}
