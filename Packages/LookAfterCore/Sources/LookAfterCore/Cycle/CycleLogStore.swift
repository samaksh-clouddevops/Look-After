import Foundation

public enum CycleLogStore {
    public static let userDefaultsKey = "lifeos.cycleDayLogs"

    public static func load() -> [CycleDayLog] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let logs = try? SharedFormatters.jsonDecoderSeconds.decode([CycleDayLog].self, from: data) else {
            return []
        }
        return logs.sorted { $0.day > $1.day }
    }

    public static func save(_ logs: [CycleDayLog]) {
        if let data = try? SharedFormatters.jsonEncoderSeconds.encode(logs) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    public static func upsert(_ log: CycleDayLog, calendar: Calendar = .current) {
        var logs = load()
        let dayStart = calendar.startOfDay(for: log.day)
        logs.removeAll { calendar.isDate($0.day, inSameDayAs: dayStart) }
        var normalized = log
        normalized.day = dayStart
        logs.append(normalized)
        save(logs.sorted { $0.day > $1.day })
    }

    public static func log(for day: Date, calendar: Calendar = .current) -> CycleDayLog? {
        load().first { calendar.isDate($0.day, inSameDayAs: day) }
    }

    public static func mergeHealthKitLogs(_ incoming: [CycleDayLog], calendar: Calendar = .current) {
        var existing = load()
        for log in incoming {
            let dayStart = calendar.startOfDay(for: log.day)
            if let index = existing.firstIndex(where: { calendar.isDate($0.day, inSameDayAs: dayStart) }) {
                var merged = existing[index]
                if merged.flow == nil { merged.flow = log.flow }
                if merged.symptoms.isEmpty { merged.symptoms = log.symptoms }
                merged.source = .healthKit
                existing[index] = merged
            } else {
                var copy = log
                copy.day = dayStart
                existing.append(copy)
            }
        }
        save(existing.sorted { $0.day > $1.day })
    }
}
