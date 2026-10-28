import Foundation

/// Commands written by widget App Intents / Live Activities; drained by the main app.
public enum WidgetCommandKind: String, Codable, Sendable, CaseIterable {
    case completeTask
    case snoozeTask
    case markMedicationTaken
    case logWater
    case startFocus
    case endFocus
    case pauseFocus
    case resumeFocus
}

public struct WidgetCommand: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var kind: WidgetCommandKind
    public var taskID: String?
    public var medicationID: String?
    public var amountMl: Double?
    public var snoozeMinutes: Int?
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        kind: WidgetCommandKind,
        taskID: String? = nil,
        medicationID: String? = nil,
        amountMl: Double? = nil,
        snoozeMinutes: Int? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.taskID = taskID
        self.medicationID = medicationID
        self.amountMl = amountMl
        self.snoozeMinutes = snoozeMinutes
        self.createdAt = createdAt
    }
}

/// App Group–backed FIFO queue for widget → app actions.
public enum WidgetCommandQueue {
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: WidgetAppGroup.identifier)
    }

    public static func enqueue(_ command: WidgetCommand) {
        var all = loadAll()
        all.append(command)
        // Cap queue length to avoid unbounded growth if app never opens.
        if all.count > 50 {
            all = Array(all.suffix(50))
        }
        saveAll(all)
    }

    public static func loadAll() -> [WidgetCommand] {
        guard
            let defaults,
            let data = defaults.data(forKey: WidgetAppGroup.commandQueueKey),
            let decoded = try? JSONDecoder().decode([WidgetCommand].self, from: data)
        else {
            return []
        }
        return decoded
    }

    /// Atomically take all pending commands and clear the queue.
    public static func drain() -> [WidgetCommand] {
        let all = loadAll()
        saveAll([])
        return all
    }

    public static func clear() {
        saveAll([])
    }

    private static func saveAll(_ commands: [WidgetCommand]) {
        guard let defaults else { return }
        if let data = try? JSONEncoder().encode(commands) {
            defaults.set(data, forKey: WidgetAppGroup.commandQueueKey)
        }
    }
}

// MARK: - Deep link routing

public enum LookAfterRoute: Equatable, Sendable {
    case recommend
    case today
    case focus
    case capture(mode: String?)
    case health
    case medication
    case brain
    case task(id: String)
    case unknown

    public static func parse(_ url: URL) -> LookAfterRoute {
        guard url.scheme == LookAfterDeepLink.scheme else { return .unknown }
        let host = (url.host ?? "").lowercased()
        switch host {
        case "recommend", "now":
            return .recommend
        case "today":
            return .today
        case "focus":
            return .focus
        case "capture":
            let mode = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "mode" })?.value
            return .capture(mode: mode)
        case "health":
            return .health
        case "medication", "meds":
            return .medication
        case "brain", "coach":
            return .brain
        case "task":
            let id = url.pathComponents.dropFirst().first ?? ""
            return id.isEmpty ? .recommend : .task(id: id)
        default:
            // lookafter:///task/id style
            let parts = url.pathComponents.filter { $0 != "/" }
            if parts.first == "task", let id = parts.dropFirst().first, !id.isEmpty {
                return .task(id: id)
            }
            return .unknown
        }
    }
}
