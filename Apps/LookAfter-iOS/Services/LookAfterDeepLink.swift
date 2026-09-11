import Foundation
import LookAfterCore

/// Handles `lookafter://` deep links from widgets, shortcuts, and notifications.
@MainActor
enum LookAfterDeepLink {
    static func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "lookafter" else { return }
        let host = (url.host ?? url.pathComponents.dropFirst().first ?? "").lowercased()
        let pathPayload = url.pathComponents
            .dropFirst()
            .filter { $0 != "/" && !$0.isEmpty }
            .joined(separator: "/")
        let queryTask = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "id" || $0.name == "taskId" })?
            .value

        switch host {
        case "today", "briefing", "":
            NotificationRouter.shared.applyRoute(.today, payload: nil)
        case "brain":
            NotificationRouter.shared.applyRoute(.brain, payload: nil)
        case "capture", "inbox":
            NotificationRouter.shared.applyRoute(.capture, payload: pathPayload.isEmpty ? nil : pathPayload)
        case "medication":
            NotificationRouter.shared.applyRoute(.medication, payload: nil)
        case "focus", "focusSession":
            NotificationRouter.shared.applyRoute(.focusSession, payload: queryTask ?? (pathPayload.isEmpty ? nil : pathPayload))
        case "task":
            let taskId = queryTask ?? (pathPayload.isEmpty ? nil : pathPayload)
            NotificationRouter.shared.applyRoute(.task, payload: taskId)
        case "emergency":
            NotificationRouter.shared.applyRoute(.emergency, payload: nil)
        default:
            NotificationRouter.shared.applyRoute(.today, payload: nil)
        }
    }
}
