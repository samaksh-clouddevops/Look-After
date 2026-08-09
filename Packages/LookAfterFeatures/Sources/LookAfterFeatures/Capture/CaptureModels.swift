import Foundation
import LookAfterCore

// MARK: - Capture intent & request

public enum CaptureIntent: String, Sendable, CaseIterable, Codable {
    case task
    case note
    case event
    case mood
    case insight
    case auto
}

public enum CaptureSource: String, Sendable, Codable {
    case bottomNav
    case briefing
    case brain
    case inbox
    case planning
    case todayTimeline
    case postFocus
    case healthDetail
    case shortcuts
}

public struct CaptureContextHints: Sendable, Equatable, Codable {
    public var screen: String?
    public var preselectedDate: Date?
    public var activeTaskId: String?
    public var moodLevel: Double?
    public var preselectedIntent: CaptureIntent?

    public init(
        screen: String? = nil,
        preselectedDate: Date? = nil,
        activeTaskId: String? = nil,
        moodLevel: Double? = nil,
        preselectedIntent: CaptureIntent? = nil
    ) {
        self.screen = screen
        self.preselectedDate = preselectedDate
        self.activeTaskId = activeTaskId
        self.moodLevel = moodLevel
        self.preselectedIntent = preselectedIntent
    }
}

public struct CaptureRequest: Sendable, Codable {
    public var text: String
    public var voiceTranscript: Bool
    public var hintedIntent: CaptureIntent?
    public var source: CaptureSource
    public var contextHints: CaptureContextHints

    public init(
        text: String,
        voiceTranscript: Bool = false,
        hintedIntent: CaptureIntent? = nil,
        source: CaptureSource = .bottomNav,
        contextHints: CaptureContextHints = CaptureContextHints()
    ) {
        self.text = text
        self.voiceTranscript = voiceTranscript
        self.hintedIntent = hintedIntent
        self.source = source
        self.contextHints = contextHints
    }
}

// MARK: - Routing result

public enum CaptureOutcome: Sendable, Equatable {
    case taskCreated(taskId: String, title: String)
    case scheduledEvent(taskId: String, title: String, scheduledAt: Date)
    case journalEntry(id: String, preview: String)
    case healthLog(mood: String, note: String?)
    case insightSaved(inboxId: String, preview: String)
    case archived
    case needsReview(inboxId: String, preview: String)
    case queuedOffline(preview: String)

    public var toastMessage: String {
        switch self {
        case .taskCreated(_, let title):
            return "Added **\(title)** to Today"
        case .scheduledEvent(_, let title, let date):
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return "Scheduled **\(title)** for \(formatter.string(from: date))"
        case .journalEntry(_, let preview):
            let snippet = String(preview.prefix(40))
            return "Saved to journal · \(snippet)"
        case .healthLog(let mood, _):
            return "Logged mood · \(mood)"
        case .insightSaved(_, let preview):
            let snippet = String(preview.prefix(40))
            return "Saved insight · \(snippet)"
        case .archived:
            return "Saved — no action needed"
        case .needsReview(_, let preview):
            let snippet = String(preview.prefix(40))
            return "Saved to Inbox for review · \(snippet)"
        case .queuedOffline(let preview):
            let snippet = String(preview.prefix(40))
            return "Saved offline · \(snippet) — will route when connected"
        }
    }

    public var plainToastMessage: String {
        toastMessage.replacingOccurrences(of: "**", with: "")
    }
}

public struct CaptureRouteResult: Sendable {
    public var outcome: CaptureOutcome
    public var inboxItemId: String?
    public var createdTaskId: String?

    public init(outcome: CaptureOutcome, inboxItemId: String? = nil, createdTaskId: String? = nil) {
        self.outcome = outcome
        self.inboxItemId = inboxItemId
        self.createdTaskId = createdTaskId
    }
}

/// Boxed payload for NotificationCenter delivery.
public final class CaptureRouteResultBox: @unchecked Sendable {
    public let result: CaptureRouteResult
    public init(_ result: CaptureRouteResult) { self.result = result }
}

// MARK: - Classifier output

public struct CaptureRoutingDecision: Sendable {
    public var intent: CaptureIntent
    public var confidence: Double
    public var title: String?
    public var summary: String?
    public var scheduledAt: Date?
    public var durationMinutes: Int?
    public var moodLabel: String?
    public var lifeArea: LifeArea?
    public var priority: Priority?
    public var difficulty: TaskDifficulty?
    public var estimatedMinutes: Int?

    public init(
        intent: CaptureIntent,
        confidence: Double,
        title: String? = nil,
        summary: String? = nil,
        scheduledAt: Date? = nil,
        durationMinutes: Int? = nil,
        moodLabel: String? = nil,
        lifeArea: LifeArea? = nil,
        priority: Priority? = nil,
        difficulty: TaskDifficulty? = nil,
        estimatedMinutes: Int? = nil
    ) {
        self.intent = intent
        self.confidence = confidence
        self.title = title
        self.summary = summary
        self.scheduledAt = scheduledAt
        self.durationMinutes = durationMinutes
        self.moodLabel = moodLabel
        self.lifeArea = lifeArea
        self.priority = priority
        self.difficulty = difficulty
        self.estimatedMinutes = estimatedMinutes
    }
}
