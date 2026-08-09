import AppIntents
import LookAfterCore

/// Widget / Live Activity intents enqueue actions for the main app to drain on foreground.
@available(iOS 17.0, *)
struct WidgetPauseFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause Focus"
    static var description = IntentDescription("Pauses the active focus session.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        AppGroupIntentStore.enqueue(action: .pauseFocus)
        return .result()
    }
}

@available(iOS 17.0, *)
struct WidgetCompleteFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Focus"
    static var description = IntentDescription("Completes the active focus session.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        AppGroupIntentStore.enqueue(action: .completeFocus)
        return .result()
    }
}

@available(iOS 17.0, *)
struct WidgetStartHeroTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Next Task"
    static var description = IntentDescription("Starts focus on your hero task.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        AppGroupIntentStore.enqueue(action: .startHeroTask)
        return .result()
    }
}
