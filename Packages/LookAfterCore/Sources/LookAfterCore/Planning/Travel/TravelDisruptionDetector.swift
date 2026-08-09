import Foundation
import LookAfterCore

public struct TravelDisruption: Sendable, Equatable {
    public var title: String
    public var departureTime: Date?
    public var summaryLine: String
    public var source: String

    public init(title: String, departureTime: Date? = nil, summaryLine: String, source: String) {
        self.title = title
        self.departureTime = departureTime
        self.summaryLine = summaryLine
        self.source = source
    }
}

/// Detects travel disruptions from calendar events and email subject lines.
public enum TravelDisruptionDetector {
    private static let fingerprintKey = "proactive.travel.fingerprint"

    public static func evaluate(
        timelineEvents: [LifeTimelineEvent],
        emailSubjects: [(id: String, subject: String, snippet: String)] = [],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TravelDisruption? {
        let travelEvents = timelineEvents.filter { event in
            let title = event.title.lowercased()
            return event.kind == .travel
                || title.contains("flight")
                || title.contains("airport")
                || title.contains("train to")
        }

        let emailTravel = emailSubjects.filter { item in
            let text = (item.subject + item.snippet).lowercased()
            return text.contains("flight") || text.contains("departure") || text.contains("gate")
        }

        var candidates: [String] = []
        candidates += travelEvents.map { "\($0.id)|\($0.title)|\(Int($0.date.timeIntervalSince1970))" }
        candidates += emailTravel.map { "email|\($0.id)|\($0.subject)" }
        let fingerprint = candidates.sorted().joined(separator: ";")
        let previous = UserDefaults.standard.string(forKey: fingerprintKey) ?? ""
        defer { UserDefaults.standard.set(fingerprint, forKey: fingerprintKey) }

        if fingerprint.isEmpty || fingerprint == previous || previous.isEmpty {
            if let event = travelEvents.first(where: { $0.date > now && calendar.isDate($0.date, inSameDayAs: now) }) {
                return TravelDisruption(
                    title: event.title,
                    departureTime: event.date,
                    summaryLine: "Travel today — \"\(event.title)\" may affect your plan.",
                    source: "calendar"
                )
            }
            return nil
        }

        if let event = travelEvents.first {
            let timeLabel = ScheduleTimeFormatting.timeLabel(event.date, calendar: calendar)
            return TravelDisruption(
                title: event.title,
                departureTime: event.date,
                summaryLine: "Travel update: \"\(event.title)\" at \(timeLabel) — replan around it?",
                source: "calendar"
            )
        }

        if let email = emailTravel.first {
            return TravelDisruption(
                title: email.subject,
                summaryLine: "New travel email: \"\(email.subject)\" — adjust your schedule?",
                source: "email"
            )
        }

        return nil
    }

    public static func proactiveAction(from disruption: TravelDisruption) -> ProactiveAction {
        ProactiveAction(
            id: "travel-disruption",
            kind: .travelDisruption,
            severity: .high,
            message: disruption.summaryLine,
            options: ["Preview replan", "Keep plan", "Dismiss"],
            surface: .autoApplyPreview,
            metadata: ["source": disruption.source, "title": disruption.title]
        )
    }

    public static func resetFingerprint() {
        UserDefaults.standard.removeObject(forKey: fingerprintKey)
    }
}
