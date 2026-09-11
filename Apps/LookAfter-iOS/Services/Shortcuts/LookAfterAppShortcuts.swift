import AppIntents
import LookAfterCore

struct WhatsNextIntent: AppIntent {
    static let title: LocalizedStringResource = "What's Next"
    static let description = IntentDescription("Speaks your orchestrated next step from Look After.")
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await LookAfterIntentBridge.shared.whatsNextBriefing(refreshLive: true)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct OverwhelmedIntent: AppIntent {
    static let title: LocalizedStringResource = "I'm Overwhelmed"
    static let description = IntentDescription("Opens anchor mode with one small task suggestion.")
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await LookAfterIntentBridge.shared.enqueueOrPerform(.overwhelmed)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct CaptureShortcutIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture Thought"
    static let description = IntentDescription("Capture a task, note, or event through Look After routing.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Text")
    var text: String

    init() {}

    init(text: String) {
        self.text = text
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(dialog: "Nothing to capture.")
        }
        let message = await LookAfterIntentBridge.shared.enqueueOrPerform(.capture, payload: trimmed)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct DeferHeroIntent: AppIntent {
    static let title: LocalizedStringResource = "Not Today"
    static let description = IntentDescription("Defers your current hero task and refreshes your plan.")
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await LookAfterIntentBridge.shared.enqueueOrPerform(.deferHero)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct TakeBreakIntent: AppIntent {
    static let title: LocalizedStringResource = "I Need a Break"
    static let description = IntentDescription("Pauses an active focus session or suggests rest.")
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await LookAfterIntentBridge.shared.enqueueOrPerform(.takeBreak)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct PauseFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause Focus"
    static let description = IntentDescription("Pauses the active focus timer.")
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        _ = await LookAfterIntentBridge.shared.enqueueOrPerform(.pauseFocus)
        return .result()
    }
}

struct CompleteFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Focus"
    static let description = IntentDescription("Ends the active focus session.")
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        _ = await LookAfterIntentBridge.shared.enqueueOrPerform(.completeFocus)
        return .result()
    }
}

struct StartHeroTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Next Task"
    static let description = IntentDescription("Starts focus on your hero task.")
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        _ = await LookAfterIntentBridge.shared.enqueueOrPerform(.startHeroTask)
        return .result()
    }
}

struct OpenCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Capture"
    static let description = IntentDescription("Opens Look After Capture.")
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await LookAfterIntentBridge.shared.enqueueOrPerform(.openCapture)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct LookAfterAppShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WhatsNextIntent(),
            phrases: [
                "What's next in \(.applicationName)",
                "What should I do in \(.applicationName)",
                "\(.applicationName) what's next"
            ],
            shortTitle: "What's Next",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: OverwhelmedIntent(),
            phrases: [
                "I'm overwhelmed in \(.applicationName)",
                "\(.applicationName) I'm overwhelmed"
            ],
            shortTitle: "Overwhelmed",
            systemImageName: "lifepreserver"
        )
        AppShortcut(
            intent: CaptureShortcutIntent(),
            phrases: [
                "Capture in \(.applicationName)",
                "\(.applicationName) capture"
            ],
            shortTitle: "Capture",
            systemImageName: "mic.circle"
        )
        AppShortcut(
            intent: OpenCaptureIntent(),
            phrases: [
                "Open capture in \(.applicationName)",
                "\(.applicationName) open capture"
            ],
            shortTitle: "Open Capture",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: DeferHeroIntent(),
            phrases: [
                "Not today in \(.applicationName)",
                "\(.applicationName) not today"
            ],
            shortTitle: "Not Today",
            systemImageName: "arrow.uturn.backward"
        )
        AppShortcut(
            intent: TakeBreakIntent(),
            phrases: [
                "I need a break in \(.applicationName)",
                "\(.applicationName) break"
            ],
            shortTitle: "Take a Break",
            systemImageName: "cup.and.saucer"
        )
        AppShortcut(
            intent: StartHeroTaskIntent(),
            phrases: [
                "Start focus in \(.applicationName)",
                "\(.applicationName) start focus"
            ],
            shortTitle: "Start Focus",
            systemImageName: "play.circle"
        )
    }
}
