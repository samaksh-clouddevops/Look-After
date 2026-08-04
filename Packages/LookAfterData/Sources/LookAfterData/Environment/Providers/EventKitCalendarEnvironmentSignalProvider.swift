import Foundation
import LookAfterCore

#if canImport(EventKit)
@preconcurrency import EventKit
#endif

/// EventKit-backed calendar signal provider (LookAfterData — not LookAfterCore).
public struct EventKitCalendarEnvironmentSignalProvider: CalendarEnvironmentSignalProviderProtocol {

    #if canImport(EventKit)
    private final class EventStoreBox: @unchecked Sendable {
        let store: EKEventStore
        init(_ store: EKEventStore) { self.store = store }
    }

    private let eventStoreBox: EventStoreBox
    private let horizonHours: Int

    public init(eventStore: EKEventStore = EKEventStore(), horizonHours: Int = 24) {
        self.eventStoreBox = EventStoreBox(eventStore)
        self.horizonHours = horizonHours
    }

    private var eventStore: EKEventStore { eventStoreBox.store }

    public func currentSignals(at date: Date) async -> CalendarEnvironmentSignals {
        let status = EKEventStore.authorizationStatus(for: .event)
        guard isAuthorized(status) else {
            return CalendarEnvironmentSignals(
                freeBlockMinutes: 0,
                isAvailable: false,
                permissionDenied: status == .denied || status == .restricted
            )
        }

        let end = date.addingTimeInterval(TimeInterval(horizonHours * 3600))
        let predicate = eventStore.predicateForEvents(withStart: date, end: end, calendars: nil)
        let events = eventStore.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }

        let nextEK = events.first { $0.startDate >= date }
        let nextEvent = nextEK.map { ek in
            CalendarEventReference(
                id: ek.eventIdentifier ?? UUID().uuidString,
                title: ek.title ?? "Event",
                startDate: ek.startDate,
                endDate: ek.endDate,
                minutesUntilStart: max(0, Int(ek.startDate.timeIntervalSince(date) / 60))
            )
        }

        let freeBlockMinutes = computeFreeBlockMinutes(from: date, to: end, events: events)
        let flowWindow = computeFlowWindow(from: date, events: events)

        return CalendarEnvironmentSignals(
            nextEvent: nextEvent,
            freeBlockMinutes: freeBlockMinutes,
            flowWindow: flowWindow,
            isAvailable: true,
            permissionDenied: false
        )
    }

    private func isAuthorized(_ status: EKAuthorizationStatus) -> Bool {
        if #available(iOS 17.0, macOS 14.0, *) {
            return status == .fullAccess || status == .writeOnly
        }
        // Legacy authorization value before iOS 17 full/write-only access levels.
        return status.rawValue == 3
    }

    private func computeFreeBlockMinutes(from start: Date, to end: Date, events: [EKEvent]) -> Int {
        guard events.isEmpty else {
            var cursor = start
            var free = 0
            for event in events where event.startDate >= start {
                if event.startDate > cursor {
                    free += Int(event.startDate.timeIntervalSince(cursor) / 60)
                }
                cursor = max(cursor, event.endDate)
            }
            if cursor < end {
                free += Int(end.timeIntervalSince(cursor) / 60)
            }
            return max(free, 0)
        }
        return max(0, Int(end.timeIntervalSince(start) / 60))
    }

    private func computeFlowWindow(from date: Date, events: [EKEvent]) -> DateInterval? {
        var cursor = date
        for event in events where event.endDate > date {
            let gapStart = max(cursor, date)
            if event.startDate > gapStart {
                let gapMinutes = event.startDate.timeIntervalSince(gapStart) / 60
                if gapMinutes >= 90 {
                    return DateInterval(start: gapStart, end: event.startDate)
                }
            }
            cursor = max(cursor, event.endDate)
        }
        return nil
    }

    #else

    public init() {}

    public func currentSignals(at date: Date) async -> CalendarEnvironmentSignals {
        CalendarEnvironmentSignals.unavailable
    }

    #endif
}

/// Always-unavailable calendar provider for tests and denied-permission scenarios.
public struct UnavailableCalendarEnvironmentSignalProvider: CalendarEnvironmentSignalProviderProtocol {
    public var permissionDenied: Bool

    public init(permissionDenied: Bool = true) {
        self.permissionDenied = permissionDenied
    }

    public func currentSignals(at date: Date) async -> CalendarEnvironmentSignals {
        CalendarEnvironmentSignals(
            freeBlockMinutes: 0,
            isAvailable: false,
            permissionDenied: permissionDenied
        )
    }
}
