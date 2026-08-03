import Foundation
import LookAfterCore
import os

/// Structured integration logging for Flow Director validation (D2.4 app wiring).
enum FlowDirectorIntegrationLog {
    private static let logger = Logger(subsystem: "com.flowos.app", category: "FlowDirector")
    private static let lastEntryKey = "flowDirectorLastLogEntry"

    struct Entry: Codable {
        var timestamp: Date
        var message: String
        var heroTask: String?
        var actionType: String?
        var confidence: Double?
        var briefingPreview: String?
        var durationMs: Double?
    }

    static func recordOrchestration(
        surface: FlowSurface,
        durationMs: Double,
        source: String = "orchestrate"
    ) {
        let preview = [surface.greeting] + surface.briefingLines
        let entry = Entry(
            timestamp: Date(),
            message: source,
            heroTask: surface.heroTask?.title,
            actionType: surface.prediction?.actionType.rawValue,
            confidence: surface.confidence,
            briefingPreview: preview.filter { !$0.isEmpty }.joined(separator: " | "),
            durationMs: durationMs
        )
        persist(entry)
        logger.info("""
        [FlowDirector] \(source) in \(String(format: "%.1f", durationMs))ms \
        hero=\(surface.heroTask?.title ?? "none", privacy: .public) \
        action=\(surface.prediction?.actionType.rawValue ?? "none", privacy: .public) \
        confidence=\(String(format: "%.2f", surface.confidence), privacy: .public)
        """)
    }

    static func log(_ message: String) {
        logger.info("[FlowDirector] \(message, privacy: .public)")
        persist(Entry(timestamp: Date(), message: message))
    }

    static func lastEntry() -> Entry? {
        guard let data = UserDefaults.standard.data(forKey: lastEntryKey),
              let entry = try? JSONDecoder().decode(Entry.self, from: data) else {
            return nil
        }
        return entry
    }

    private static func persist(_ entry: Entry) {
        if let data = try? JSONEncoder().encode(entry) {
            UserDefaults.standard.set(data, forKey: lastEntryKey)
        }
    }
}
