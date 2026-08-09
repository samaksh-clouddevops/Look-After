import Foundation

/// Collapses repeated cascade log entries from frequent schedule reconciles.
enum CascadeHistoryDedup {

    static func compact(_ records: [CascadeActionRecord], calendar: Calendar = .current) -> [CascadeActionRecord] {
        var result: [CascadeActionRecord] = []
        for record in records.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard !isDuplicate(record, in: result, calendar: calendar) else { continue }
            result.append(record)
        }
        return result
    }

    static func merge(
        incoming: [CascadeActionRecord],
        into history: [CascadeActionRecord],
        calendar: Calendar = .current
    ) -> [CascadeActionRecord] {
        var merged = history
        for record in incoming {
            guard !isDuplicate(record, in: merged, calendar: calendar) else { continue }
            merged.append(record)
        }
        return merged
    }

    static func isDuplicate(
        _ record: CascadeActionRecord,
        in existing: [CascadeActionRecord],
        calendar: Calendar
    ) -> Bool {
        let day = TelemetryLogRotation.dayKey(for: record.timestamp, calendar: calendar)
        switch record.kind {
        case .shiftedLater, .superseded, .expired, .compressed, .deferred, .parked:
            guard let taskID = record.taskID else { return false }
            return existing.contains {
                TelemetryLogRotation.dayKey(for: $0.timestamp, calendar: calendar) == day
                    && $0.kind == record.kind
                    && $0.taskID == taskID
            }
        case .sabotageAuction:
            return existing.contains {
                TelemetryLogRotation.dayKey(for: $0.timestamp, calendar: calendar) == day
                    && $0.kind == .sabotageAuction
            }
        case .other:
            return false
        }
    }
}
