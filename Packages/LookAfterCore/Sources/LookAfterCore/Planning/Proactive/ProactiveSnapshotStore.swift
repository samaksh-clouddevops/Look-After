import Foundation

/// Persists last foreground proactive actions for background notification refresh.
public enum ProactiveSnapshotStore {
    private static let key = "lookafter.proactive.snapshot"

    public static func save(_ actions: [ProactiveAction]) {
        let payload = actions.map { SnapshotAction(from: $0) }
        if let data = try? SharedFormatters.jsonEncoderSeconds.encode(payload) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    public static func load() -> [ProactiveAction] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? SharedFormatters.jsonDecoderSeconds.decode([SnapshotAction].self, from: data) else {
            return []
        }
        return decoded.map(\.action)
    }

    public static func resetForFactoryReset() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private struct SnapshotAction: Codable {
        var id: String
        var kind: String
        var severity: String
        var message: String
        var options: [String]
        var surface: String
        var relatedTaskIDs: [String]
        var relatedInboxIDs: [String]
        var expiresAt: Date?
        var metadata: [String: String]

        init(from action: ProactiveAction) {
            id = action.id
            kind = action.kind.rawValue
            severity = action.severity.rawValue
            message = action.message
            options = action.options
            surface = action.surface.rawValue
            relatedTaskIDs = action.relatedTaskIDs
            relatedInboxIDs = action.relatedInboxIDs
            expiresAt = action.expiresAt
            metadata = action.metadata
        }

        var action: ProactiveAction {
            ProactiveAction(
                id: id,
                kind: ProactiveAction.Kind(rawValue: kind) ?? .morningPlanReview,
                severity: ProactiveAction.Severity(rawValue: severity) ?? .medium,
                message: message,
                options: options,
                surface: ProactiveAction.Surface(rawValue: surface) ?? .banner,
                relatedTaskIDs: relatedTaskIDs,
                relatedInboxIDs: relatedInboxIDs,
                expiresAt: expiresAt,
                metadata: metadata
            )
        }
    }
}
