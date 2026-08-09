import Foundation

/// Actions queued by Siri, Shortcuts, widgets, or Live Activity when the app is not foreground-ready.
public enum PendingShortcutAction: String, Codable, Sendable, CaseIterable {
    case whatsNext
    case capture
    case deferHero
    case overwhelmed
    case takeBreak
    case pauseFocus
    case completeFocus
    case startHeroTask
}

public struct PendingShortcutRequest: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var action: PendingShortcutAction
    public var payload: String?
    public var queuedAt: Date

    public init(
        id: String = UUID().uuidString,
        action: PendingShortcutAction,
        payload: String? = nil,
        queuedAt: Date = Date()
    ) {
        self.id = id
        self.action = action
        self.payload = payload
        self.queuedAt = queuedAt
    }
}

/// App Group file store for shortcut / Siri pending actions (shared with widget extension).
public enum AppGroupIntentStore {
    private static let fileName = "pending-shortcut-actions.json"

    private static var inMemoryFallback: [PendingShortcutRequest] = []

    public static var isAvailable: Bool {
        AppGroupWidgetStore.isAvailable
    }

    /// Uses App Group on device; falls back to in-process storage when the container is unavailable (tests, previews).
    private static var usesInMemoryFallback: Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return true
        }
        if NSClassFromString("XCTestCase") != nil {
            return true
        }
        return !isAvailable
    }

    private static var fileURL: URL? {
        AppGroupWidgetStore.containerURL()?.appendingPathComponent(fileName, isDirectory: false)
    }

    public static func enqueue(_ request: PendingShortcutRequest) {
        var queue = loadAll()
        queue.append(request)
        save(queue)
    }

    public static func enqueue(action: PendingShortcutAction, payload: String? = nil) {
        enqueue(PendingShortcutRequest(action: action, payload: payload))
    }

    @discardableResult
    public static func dequeueAll() -> [PendingShortcutRequest] {
        let queue = loadAll()
        save([])
        return queue
    }

    public static func pending() -> [PendingShortcutRequest] {
        loadAll()
    }

    public static func clear() {
        inMemoryFallback = []
        save([])
    }

    private static func loadAll() -> [PendingShortcutRequest] {
        if usesInMemoryFallback {
            return inMemoryFallback
        }
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? SharedFormatters.jsonDecoderSeconds.decode([PendingShortcutRequest].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func save(_ queue: [PendingShortcutRequest]) {
        if usesInMemoryFallback {
            inMemoryFallback = queue
            return
        }
        guard let url = fileURL else { return }
        guard let data = try? SharedFormatters.jsonEncoderSeconds.encode(queue) else { return }
        try? data.write(to: url, options: [.atomic])
    }
}
