import XCTest
@testable import LookAfterCore

final class DepartureTimePredictorTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func day() -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 10))!
    }

    func testPredictsDepartureBeforeArrivalTime() {
        let prediction = DepartureTimePredictor.predict(
            originLatitude: 37.3346,
            originLongitude: -122.0090,
            destinationLatitude: 37.4419,
            destinationLongitude: -122.1430,
            arrivalHour: 10,
            arrivalMinute: 0,
            on: day(),
            calendar: calendar
        )

        XCTAssertNotNil(prediction)
        guard let prediction else { return }
        XCTAssertLessThan(prediction.departureDate, prediction.arrivalDate)
        XCTAssertGreaterThan(prediction.travelMinutes, 0)
        XCTAssertGreaterThan(prediction.distanceKm, 0)

        var expectedArrivalComponents = DateComponents(year: 2026, month: 9, day: 10, hour: 10, minute: 0)
        expectedArrivalComponents.timeZone = calendar.timeZone
        let expectedArrival = calendar.date(from: expectedArrivalComponents)
        XCTAssertEqual(prediction.arrivalDate, expectedArrival)
    }

    func testReturnsNilForCoincidentCoordinates() {
        let prediction = DepartureTimePredictor.predict(
            originLatitude: 37.3346,
            originLongitude: -122.0090,
            destinationLatitude: 37.3346,
            destinationLongitude: -122.0090,
            arrivalHour: 9,
            arrivalMinute: 0,
            on: day(),
            calendar: calendar
        )
        XCTAssertNil(prediction)
    }

    func testLongerDistanceYieldsLongerTravelTime() {
        let short = DepartureTimePredictor.predict(
            originLatitude: 37.3346,
            originLongitude: -122.0090,
            destinationLatitude: 37.3446,
            destinationLongitude: -122.0190,
            arrivalHour: 9,
            arrivalMinute: 0,
            on: day(),
            calendar: calendar
        )
        let long = DepartureTimePredictor.predict(
            originLatitude: 37.3346,
            originLongitude: -122.0090,
            destinationLatitude: 37.7749,
            destinationLongitude: -122.4194,
            arrivalHour: 9,
            arrivalMinute: 0,
            on: day(),
            calendar: calendar
        )

        XCTAssertNotNil(short)
        XCTAssertNotNil(long)
        guard let short, let long else { return }
        XCTAssertLessThan(short.travelMinutes, long.travelMinutes)
    }
}
