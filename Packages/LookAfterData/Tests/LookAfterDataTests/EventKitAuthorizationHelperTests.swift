import XCTest
@testable import LookAfterData
import EventKit

final class EventKitAuthorizationHelperTests: XCTestCase {
    func testAuthorizationMatchesPriorProductBehavior() {
        // writeOnly kept authorized so calendar-dependent UI is not restricted.
        XCTAssertTrue(EventKitCalendarEnvironmentSignalProvider.canReadEvents(.writeOnly))
        XCTAssertTrue(EventKitCalendarEnvironmentSignalProvider.canReadEvents(.fullAccess))
        XCTAssertFalse(EventKitCalendarEnvironmentSignalProvider.canReadEvents(.denied))
        XCTAssertFalse(EventKitCalendarEnvironmentSignalProvider.canReadEvents(.notDetermined))
    }
}
