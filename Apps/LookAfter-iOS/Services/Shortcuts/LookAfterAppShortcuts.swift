import AppIntents
import LookAfterCore

@available(iOS 17.0, *)
struct WhatsNextIntent: AppIntent {
    static var title: LocalizedStringResource = "What's Next"
    static var description = IntentDescription("Speaks your orchestrated next step from Look After.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await LookAfterIntentBridge.shared.whatsNextBriefing(refreshLive: true)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

@available(iOS 17.0, *)
struct OverwhelmedIntent: AppIntent {
    static var title: LocalizedStringResource = "I'm Overwhelmed"
    static var description = IntentDescription("Opens anchor mode with one small task suggestion.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await LookAfterIntentBridge.shared.enqueueOrPerform(.overwhelmed)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

@available(iOS 17.0, *)
struct CaptureShortcutIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture Thought"
    static var description = IntentDescription("Capture a task, note, or event through Look After routing.")
    static var openAppWhenRun: Bool = false

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

@available(iOS 17.0, *)
struct DeferHeroIntent: AppIntent {
    static var title: LocalizedStringResource = "Not Today"
    static var description = IntentDescription("Defers your current hero task and refreshes your plan.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await LookAfterIntentBridge.shared.enqueueOrPerform(.deferHero)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

@available(iOS 17.0, *)
struct TakeBreakIntent: AppIntent {
    static var title: LocalizedStringResource = "I Need a Break"
    static var description = IntentDescription("Pauses an active focus session or suggests rest.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await LookAfterIntentBridge.shared.enqueueOrPerform(.takeBreak)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

@available(iOS 17.0, *)
struct PauseFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause Focus"
    static var description = IntentDescription("Pauses the active focus timer.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        _ = await LookAfterIntentBridge.shared.enqueueOrPerform(.pauseFocus)
        return .result()
    }
}

@available(iOS 17.0, *)
struct CompleteFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Focus"
    static var description = IntentDescription("Ends the active focus session.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        _ = await LookAfterIntentBridge.shared.enqueueOrPerform(.completeFocus)
        return .result()
    }
}

@available(iOS 17.0, *)
struct StartHeroTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Next Task"
    static var description = IntentDescription("Starts focus on your hero task.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        _ = await LookAfterIntentBridge.shared.enqueueOrPerform(.startHeroTask)
        return .result()
    }
}

@available(iOS 17.0, *)
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
