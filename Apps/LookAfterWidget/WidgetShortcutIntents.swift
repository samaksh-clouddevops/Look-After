import AppIntents
import LookAfterCore

/// Widget / Live Activity intents enqueue actions for the main app to drain on foreground.
struct WidgetPauseFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause Focus"
    static let description = IntentDescription("Pauses the active focus session.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        AppGroupIntentStore.enqueue(action: .pauseFocus)
        return .result()
    }
}

struct WidgetCompleteFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Focus"
    static let description = IntentDescription("Completes the active focus session.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        AppGroupIntentStore.enqueue(action: .completeFocus)
        return .result()
    }
}

struct WidgetStartHeroTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Next Task"
    static let description = IntentDescription("Starts focus on your hero task.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        AppGroupIntentStore.enqueue(action: .startHeroTask)
        return .result()
    }
}

struct WidgetOpenCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture"
    static let description = IntentDescription("Opens Look After Capture.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        AppGroupIntentStore.enqueue(action: .openCapture)
        return .result()
    }
}
