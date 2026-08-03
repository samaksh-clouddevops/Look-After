import Foundation

public enum CalibrationSource: String, Codable, Sendable {
    case journal
    case manual
    case insights
    case cycle
}

/// One learned calibration from journal reflection or explicit user feedback.
public struct UserCalibrationEntry: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let createdAt: Date
    public let source: CalibrationSource
    public let summary: String
    public let rawInput: String?

    public init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        source: CalibrationSource,
        summary: String,
        rawInput: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.source = source
        self.summary = summary
        self.rawInput = rawInput
    }
}

/// Persists qualitative task-duration and energy calibrations learned from journal + insights.
public enum UserCalibrationStore {
    public static let storageKey = "lifeos.userCalibrations"
    private static let maxEntries = 50

    public static func load() -> [UserCalibrationEntry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let entries = try? JSONDecoder().decode([UserCalibrationEntry].self, from: data) else {
            return []
        }
        return entries.sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    public static func append(
        summary: String,
        source: CalibrationSource,
        rawInput: String? = nil
    ) -> UserCalibrationEntry {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return UserCalibrationEntry(source: source, summary: "")
        }

        var entries = load()
        let entry = UserCalibrationEntry(source: source, summary: trimmed, rawInput: rawInput)
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save(entries)
        return entry
    }

    public static func promptBlock(maxEntries: Int = 8) -> String {
        let recent = load().prefix(maxEntries).map(\.summary).filter { !$0.isEmpty }
        guard !recent.isEmpty else { return "" }
        let lines = recent.enumerated().map { index, summary in
            "\(index + 1). \(summary)"
        }.joined(separator: "\n")
        return """
        LEARNED CALIBRATIONS (from journal + feedback — trust these over defaults):
        \(lines)
        """
    }

    /// Merges behavioral analytics with qualitative calibrations for coach / personalization.
    public static func combinedPersonalizationBlock(analyticsBlock: String?) -> String? {
        var parts: [String] = []
        if let analyticsBlock, !analyticsBlock.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(analyticsBlock.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let calibration = promptBlock()
        if !calibration.isEmpty {
            parts.append(calibration)
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "\n\n")
    }

    public static func reset() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    private static func save(_ entries: [UserCalibrationEntry]) {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
