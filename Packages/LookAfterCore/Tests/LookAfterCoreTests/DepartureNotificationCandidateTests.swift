import XCTest
@testable import LookAfterCore

final class DepartureNotificationCandidateTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: hour, minute: minute))!
    }

    func testNoDepartureCandidateWhenContextMissing() {
        let input = NotificationRefreshInput(now: date(7, 0), departureContext: nil)
        let candidates = NotificationCandidateBuilder.build(from: input, calendar: calendar)
        XCTAssertFalse(candidates.contains { $0.kind == .departureReminder })
    }

    func testDepartureCandidateFiresBeforeArrival() {
        let context = DepartureNotificationContext(
            originLatitude: 37.3346,
            originLongitude: -122.0090,
            destinationLatitude: 37.4419,
            destinationLongitude: -122.1430,
            destinationLabel: "office",
            arrivalHour: 10,
            arrivalMinute: 0
        )
        let input = NotificationRefreshInput(now: date(7, 0), departureContext: context)
        let candidates = NotificationCandidateBuilder.build(from: input, calendar: calendar)

        guard let candidate = candidates.first(where: { $0.kind == .departureReminder }) else {
            XCTFail("Expected a departure candidate")
            return
        }
        XCTAssertLessThan(candidate.fireDate, date(10, 0))
        XCTAssertTrue(candidate.body.contains("office"))
    }

    func testNoDepartureCandidateWhenPredictedDepartureAlreadyPassed() {
        let context = DepartureNotificationContext(
            originLatitude: 37.3346,
            originLongitude: -122.0090,
            destinationLatitude: 37.4419,
            destinationLongitude: -122.1430,
            destinationLabel: "office",
            arrivalHour: 10,
            arrivalMinute: 0
        )
        // Now is already past arrival time — nothing to predict for today.
        let input = NotificationRefreshInput(now: date(11, 0), departureContext: context)
        let candidates = NotificationCandidateBuilder.build(from: input, calendar: calendar)
        XCTAssertFalse(candidates.contains { $0.kind == .departureReminder })
    }
}
