import Foundation
import EventKit
import LookAfterCore
import LookAfterData

/// Progressive onboarding: only runs after the user taps "Analyze My Schedule".
/// Never call from cold launch — fire the system prompt only on that CTA.
@MainActor
public final class CalendarBaselineAnalyzer {
    public static let shared = CalendarBaselineAnalyzer()

    private let eventStore = EKEventStore()

    public init() {}

    public enum AnalyzeError: Error, LocalizedError {
        case accessDenied
        case noEvents

        public var errorDescription: String? {
            switch self {
            case .accessDenied:
                return "Calendar access was not granted."
            case .noEvents:
                return "No qualifying events found in the last 6 months."
            }
        }
    }

    /// Copy for the dedicated trust screen (on-device promise).
    public static let trustScreenHeadline = "Build your baseline from real life"
    public static let trustScreenBody = """
    Look After maps your past 6 months of schedules into a mathematical rhythm — entirely on your device. \
    Nothing is uploaded. Birthdays, PTO, and subscribed calendars are filtered out automatically.
    """
    public static let trustScreenCTA = "Analyze My Schedule"

    /// Request access only after explicit CTA, fetch 6 months, poison-filter, seed vault.
    public func analyzeAndSeed(
        now: Date = Date(),
        calendar: Calendar = .current
    ) async throws -> (seeded: Bool, profile: RhythmProfile, eventCount: Int) {
        let granted = try await eventStore.requestFullAccessToEvents()
        guard granted else { throw AnalyzeError.accessDenied }

        let end = now
        guard let start = calendar.date(byAdding: .day, value: -CalendarRhythmAnalyzer.historyDays, to: end) else {
            throw AnalyzeError.noEvents
        }

        // Prefer local calendars; mark subscribed for poison filter.
        let cals = eventStore.calendars(for: .event)
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: cals)
        let ekEvents = eventStore.events(matching: predicate)

        var history: [CalendarHistoryEvent] = []
        var meta: [String: CalendarEventSourceMeta] = [:]

        for ek in ekEvents {
            let id = ek.eventIdentifier ?? UUID().uuidString
            let calType = ek.calendar?.type
            let isSubscribed = calType == .subscription || calType == .birthday
            let item = CalendarHistoryEvent(
                id: id,
                start: ek.startDate,
                end: ek.endDate,
                isAllDay: ek.isAllDay,
                title: ek.title ?? ""
            )
            history.append(item)
            meta[id] = CalendarEventSourceMeta(
                isAllDay: ek.isAllDay,
                isSubscribedCalendar: isSubscribed,
                calendarTitle: ek.calendar?.title ?? "",
                eventTitle: ek.title ?? ""
            )
        }

        let clean = CalendarEventPoisonFilter.filter(history, metaByID: meta)
        guard !clean.isEmpty else { throw AnalyzeError.noEvents }

        let store = BehavioralVaultStore()
        let result = await store.seedFromCalendarHistory(
            events: history,
            metaByID: meta,
            now: now,
            calendar: calendar
        )
        return (result.seeded, result.profile, clean.count)
    }
}
