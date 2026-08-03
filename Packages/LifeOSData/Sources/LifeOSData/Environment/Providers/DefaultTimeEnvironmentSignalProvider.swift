import Foundation
import LifeOSCore

/// Pure Foundation time-of-day provider — always available, no permissions required.
public struct DefaultTimeEnvironmentSignalProvider: TimeEnvironmentSignalProviderProtocol {

    public init() {}

    public func currentSignals(at date: Date, calendar: Calendar = .current) async -> TimeEnvironmentSignals {
        TimeEnvironmentSignals(
            timeOfDay: TimeOfDay.from(date: date, calendar: calendar),
            isWeekend: calendar.isDateInWeekend(date),
            isAvailable: true
        )
    }
}
