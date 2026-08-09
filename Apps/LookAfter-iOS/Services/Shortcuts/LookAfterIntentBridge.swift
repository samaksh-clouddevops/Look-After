import Foundation
import LookAfterCore
import LookAfterData
import LookAfterFeatures

/// Bridges Siri / Shortcuts App Intents to Executive Brain when the app is foreground,
/// or enqueues actions via App Group when backgrounded.
@MainActor
final class LookAfterIntentBridge {
    static let shared = LookAfterIntentBridge()

    weak var shell: AppShellState?
    private(set) var cachedUserId: String = ""

    private init() {}

    func register(shell: AppShellState, userId: String) {
        self.shell = shell
        self.cachedUserId = userId
    }

    // MARK: - Read-only briefing

    func whatsNextBriefing(refreshLive: Bool = true) async -> String {
        if refreshLive, let shell, let userId = resolvedUserId(from: shell) {
            await shell.orchestrateBrain(userId: userId)
        }

        if let surface = shell?.brainVM.flowSurface, !surface.briefingText.isEmpty {
            return UserFacingCopy.sanitize(surface.briefingText)
        }
        if let recommendation = shell?.brainVM.recommendation, !recommendation.isEmpty {
            return UserFacingCopy.sanitize(recommendation)
        }

        let snapshot = WidgetDataStore.load()
        if !snapshot.recommendation.isEmpty {
            return UserFacingCopy.sanitize(snapshot.recommendation)
        }
        if let title = snapshot.resolvedTopTaskTitle {
            return "Your next step is \(title)."
        }
        return "Open Look After to see your next step."
    }

    // MARK: - Mutations (live or queued)

    @discardableResult
    func enqueueOrPerform(
        _ action: PendingShortcutAction,
        payload: String? = nil,
        userId: String? = nil
    ) async -> String {
        if let shell, let uid = userId ?? resolvedUserId(from: shell) ?? (cachedUserId.isEmpty ? nil : cachedUserId) {
            if await perform(action: action, payload: payload, userId: uid, shell: shell) {
                return dialogForCompleted(action: action, payload: payload, shell: shell)
            }
        }

        AppGroupIntentStore.enqueue(action: action, payload: payload)
        return dialogForQueued(action: action, payload: payload)
    }

    func processPendingQueue(userId: String) async {
        guard let shell else { return }
        let pending = AppGroupIntentStore.dequeueAll()
        guard !pending.isEmpty else { return }

        for request in pending {
            _ = await perform(action: request.action, payload: request.payload, userId: userId, shell: shell)
        }

        shell.refreshWidgetData()
    }

    // MARK: - Private

    private func resolvedUserId(from shell: AppShellState) -> String? {
        let id = shell.tasksVM.tasks.first?.userId ?? shell.inboxVM.items.first?.userId ?? ""
        return id.isEmpty ? nil : id
    }

    @discardableResult
    private func perform(
        action: PendingShortcutAction,
        payload: String?,
        userId: String,
        shell: AppShellState
    ) async -> Bool {
        switch action {
        case .whatsNext:
            await shell.orchestrateBrain(userId: userId)
            return true

        case .capture:
            let text = payload?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return false }
            _ = await shell.inboxVM.routeCapture(
                CaptureRequest(
                    text: text,
                    source: .shortcuts,
                    contextHints: CaptureContextHints(screen: "shortcuts")
                ),
                userId: userId
            )
            return true

        case .deferHero:
            let hero = resolveHeroTask(shell: shell)
            guard let hero else { return false }
            await shell.brainVM.handleTaskDeferred(hero, userId: userId)
            await shell.orchestrateBrain(userId: userId)
            return true

        case .overwhelmed:
            shell.adhdVM.activateEmergencyMode(allTasks: shell.tasksVM.tasks)
            NotificationRouter.shared.applyRoute(.emergency, payload: nil)
            return true

        case .takeBreak, .pauseFocus:
            if shell.adhdVM.isFocusSessionActive {
                shell.adhdVM.pauseFocusSession()
                return true
            }
            return false

        case .completeFocus:
            if shell.adhdVM.isFocusSessionActive {
                shell.adhdVM.endFocusSession()
                return true
            }
            return false

        case .startHeroTask:
            let taskId = payload ?? WidgetDataStore.load().heroTaskId ?? WidgetDataStore.load().tasks.first?.id
            guard let taskId,
                  let task = shell.tasksVM.tasks.first(where: { $0.id == taskId && $0.status.isActive }) else {
                return false
            }
            shell.adhdVM.startFocusSession(task: task)
            NotificationRouter.shared.applyRoute(.focusSession, payload: taskId)
            return true
        }
    }

    private func resolveHeroTask(shell: AppShellState) -> LifeTask? {
        if let hero = shell.brainVM.flowSurface?.heroTask { return hero }
        if let id = WidgetDataStore.load().heroTaskId {
            return shell.tasksVM.tasks.first { $0.id == id && $0.status.isActive }
        }
        return shell.brainVM.topTasks.first
    }

    private func dialogForCompleted(action: PendingShortcutAction, payload: String?, shell: AppShellState) -> String {
        switch action {
        case .whatsNext:
            return "Checking your plan."
        case .capture:
            return "Captured."
        case .deferHero:
            return "Deferred to another time."
        case .overwhelmed:
            let suggestion = shell.adhdVM.emergencyTasks.first?.title
                ?? shell.brainVM.flowSurface?.heroTask?.title
                ?? "one small task"
            return "Anchor mode on. Try \(suggestion)."
        case .takeBreak, .pauseFocus:
            return shell.adhdVM.isFocusSessionActive ? "Paused your focus session." : "Take a breather."
        case .completeFocus:
            return "Focus session complete."
        case .startHeroTask:
            return "Starting focus."
        }
    }

    private func dialogForQueued(action: PendingShortcutAction, payload: String?) -> String {
        switch action {
        case .whatsNext:
            return "Open Look After for your full briefing."
        case .capture:
            return "Saved capture — will route when you open Look After."
        case .deferHero:
            return "Will defer your hero task when you open Look After."
        case .overwhelmed:
            return "Open Look After for anchor mode."
        case .takeBreak, .pauseFocus:
            return "Will pause focus when you open Look After."
        case .completeFocus:
            return "Will complete focus when you open Look After."
        case .startHeroTask:
            return "Open Look After to start focus."
        }
    }
}
