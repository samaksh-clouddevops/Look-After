import AppIntents
import WidgetKit
import LookAfterCore

// MARK: - Helpers

private enum WidgetIntentSupport {
    static func snapshot() -> WidgetSnapshot {
        WidgetSnapshotStore.load()
    }

    static func enqueue(_ command: WidgetCommand) {
        WidgetCommandQueue.enqueue(command)
        // Nudge home-screen widgets; main app drains queue on launch/foreground.
        for kind in [
            LookAfterWidgetKind.recommendation,
            LookAfterWidgetKind.today,
            LookAfterWidgetKind.focus,
            LookAfterWidgetKind.health,
            LookAfterWidgetKind.capture,
            LookAfterWidgetKind.medication
        ] {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
    }
}

// MARK: - Complete recommendation / task

struct CompleteWidgetTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Task"
    static var description = IntentDescription("Marks the recommended task complete.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Task ID")
    var taskID: String?

    init() {}
    init(taskID: String?) { self.taskID = taskID }

    func perform() async throws -> some IntentResult {
        let id = taskID ?? WidgetIntentSupport.snapshot().resolvedRecommendation.taskID
        guard let id, !id.isEmpty else {
            return .result()
        }
        WidgetIntentSupport.enqueue(WidgetCommand(kind: .completeTask, taskID: id))
        return .result()
    }
}

// MARK: - Snooze

struct SnoozeWidgetTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Snooze Task"
    static var description = IntentDescription("Defers the recommended task by one hour.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Task ID")
    var taskID: String?

    @Parameter(title: "Minutes")
    var minutes: Int?

    init() {}
    init(taskID: String?, minutes: Int = 60) {
        self.taskID = taskID
        self.minutes = minutes
    }

    func perform() async throws -> some IntentResult {
        let id = taskID ?? WidgetIntentSupport.snapshot().resolvedRecommendation.taskID
        guard let id, !id.isEmpty else { return .result() }
        WidgetIntentSupport.enqueue(
            WidgetCommand(kind: .snoozeTask, taskID: id, snoozeMinutes: minutes ?? 60)
        )
        return .result()
    }
}

// MARK: - Medication

struct MarkMedicationTakenIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark Medication Taken"
    static var description = IntentDescription("Records that the due medication was taken. No medical advice.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Medication ID")
    var medicationID: String?

    init() {}
    init(medicationID: String?) { self.medicationID = medicationID }

    func perform() async throws -> some IntentResult {
        let id = medicationID ?? WidgetIntentSupport.snapshot().medication?.id
        guard let id, !id.isEmpty else { return .result() }
        WidgetIntentSupport.enqueue(WidgetCommand(kind: .markMedicationTaken, medicationID: id))
        return .result()
    }
}

// MARK: - Water

struct LogWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Water"
    static var description = IntentDescription("Logs 250 ml of water.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Milliliters")
    var amountMl: Double?

    init() {}
    init(amountMl: Double = 250) { self.amountMl = amountMl }

    func perform() async throws -> some IntentResult {
        WidgetIntentSupport.enqueue(
            WidgetCommand(kind: .logWater, amountMl: amountMl ?? 250)
        )
        return .result()
    }
}

// MARK: - Focus

struct StartFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Focus"
    static var description = IntentDescription("Starts a focus session on the recommended task.")
    /// Open app so focus UI can present; command also queued for reliability.
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Task ID")
    var taskID: String?

    init() {}
    init(taskID: String?) { self.taskID = taskID }

    func perform() async throws -> some IntentResult {
        let id = taskID ?? WidgetIntentSupport.snapshot().resolvedRecommendation.taskID
        WidgetIntentSupport.enqueue(WidgetCommand(kind: .startFocus, taskID: id))
        return .result()
    }
}

struct EndFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "End Focus"
    static var description = IntentDescription("Ends the active focus session.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        WidgetIntentSupport.enqueue(WidgetCommand(kind: .endFocus))
        return .result()
    }
}

struct PauseFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause Focus"
    static var description = IntentDescription("Pauses or resumes the active focus session.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        WidgetIntentSupport.enqueue(WidgetCommand(kind: .pauseFocus))
        return .result()
    }
}
