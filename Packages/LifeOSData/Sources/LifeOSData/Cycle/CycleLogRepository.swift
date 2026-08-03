import Foundation
import LifeOSCore

/// Repository facade for cycle logs — local persistence with optional future cloud sync.
public enum CycleLogRepository {
    public static func load() -> [CycleDayLog] {
        CycleLogStore.load()
    }

    public static func save(_ logs: [CycleDayLog]) {
        CycleLogStore.save(logs)
    }

    public static func upsert(_ log: CycleDayLog) {
        CycleLogStore.upsert(log)
        appendCalibrationIfNeeded(from: log)
    }

    public static func mergeHealthKitLogs(_ logs: [CycleDayLog]) {
        CycleLogStore.mergeHealthKitLogs(logs)
    }

    private static func appendCalibrationIfNeeded(from log: CycleDayLog) {
        guard !log.symptoms.isEmpty || log.energy != nil else { return }
        var parts: [String] = []
        if let energy = log.energy {
            parts.append("energy \(energy)/5")
        }
        if !log.symptoms.isEmpty {
            parts.append("symptoms: \(log.symptoms.joined(separator: ", "))")
        }
        guard !parts.isEmpty else { return }
        UserCalibrationStore.append(
            summary: "Cycle log — \(parts.joined(separator: "; "))",
            source: .cycle,
            rawInput: log.notes
        )
    }
}
