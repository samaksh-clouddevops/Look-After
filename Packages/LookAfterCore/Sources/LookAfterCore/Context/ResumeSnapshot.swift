import Foundation

/// Cross-session resume state — what the user was doing when they left.
public struct ResumeSnapshot: Codable, Sendable, Equatable {
    public var lastScreen: String
    public var lastFile: String?
    public var lastNote: String?
    public var lastTimerTaskID: String?
    public var lastTimerTaskTitle: String?
    public var lastTimerElapsedSeconds: Int?
    public var lastDocument: String?
    public var lastBrowserLink: String?
    public var lastAIConversationPreview: String?
    public var lastTaskID: String?
    public var lastTaskTitle: String?
    public var workingContext: WorkingContext?
    public var experienceMode: ExperienceMode?
    /// Privacy-safe blurred snapshot of last context (JPEG/PNG bytes). Optional until capture pipeline ships.
    public var previewImageData: Data?
    public var savedAt: Date

    public init(
        lastScreen: String = "today",
        lastFile: String? = nil,
        lastNote: String? = nil,
        lastTimerTaskID: String? = nil,
        lastTimerTaskTitle: String? = nil,
        lastTimerElapsedSeconds: Int? = nil,
        lastDocument: String? = nil,
        lastBrowserLink: String? = nil,
        lastAIConversationPreview: String? = nil,
        lastTaskID: String? = nil,
        lastTaskTitle: String? = nil,
        workingContext: WorkingContext? = nil,
        experienceMode: ExperienceMode? = nil,
        previewImageData: Data? = nil,
        savedAt: Date = Date()
    ) {
        self.lastScreen = lastScreen
        self.lastFile = lastFile
        self.lastNote = lastNote
        self.lastTimerTaskID = lastTimerTaskID
        self.lastTimerTaskTitle = lastTimerTaskTitle
        self.lastTimerElapsedSeconds = lastTimerElapsedSeconds
        self.lastDocument = lastDocument
        self.lastBrowserLink = lastBrowserLink
        self.lastAIConversationPreview = lastAIConversationPreview
        self.lastTaskID = lastTaskID
        self.lastTaskTitle = lastTaskTitle
        self.workingContext = workingContext
        self.experienceMode = experienceMode
        self.previewImageData = previewImageData
        self.savedAt = savedAt
    }

    /// Human-readable resume line for the Home screen.
    public var resumeDetail: String? {
        if let context = workingContext {
            if let subtitle = context.subtitle, !subtitle.isEmpty {
                return "\(context.title) · \(subtitle)"
            }
            return context.title
        }
        if let title = lastTaskTitle { return title }
        if let note = lastNote { return note }
        if let doc = lastDocument { return doc }
        if let file = lastFile { return file }
        if let link = lastBrowserLink { return link }
        if let preview = lastAIConversationPreview { return preview }
        return nil
    }

    public var isStale: Bool {
        Date().timeIntervalSince(savedAt) > 86_400
    }
}
