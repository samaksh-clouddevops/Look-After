import Foundation

/// The type of content captured in the universal inbox.
public enum InboxItemType: String, Codable, CaseIterable, Sendable {
    case text = "Text"
    case voiceMemo = "Voice Memo"
    case photo = "Photo"
    case screenshot = "Screenshot"
    case link = "Link"
    case pdf = "PDF"
    case email = "Email"
    case note = "Note"
    
    public var icon: String {
        switch self {
        case .text: return "text.alignleft"
        case .voiceMemo: return "mic.fill"
        case .photo: return "photo.fill"
        case .screenshot: return "camera.viewfinder"
        case .link: return "link"
        case .pdf: return "doc.fill"
        case .email: return "envelope.fill"
        case .note: return "note.text"
        }
    }
}

/// Processing status of an inbox item.
public enum InboxItemStatus: String, Codable, CaseIterable, Sendable {
    case unprocessed = "Unprocessed"
    case processing = "Processing"
    case categorized = "Categorized"
    case actionCreated = "Action Created"
    case archived = "Archived"
    case dismissed = "Dismissed"
}

/// A universal inbox item — anything the user captures goes here first.
/// AI automatically categorizes, prioritizes, and creates actions from inbox items.
public struct InboxItem: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var content: String
    public var type: InboxItemType
    public var status: InboxItemStatus
    public var lifeArea: LifeArea?
    public var suggestedPriority: Priority?
    public var aiSummary: String?
    public var aiSuggestedAction: String?
    public var attachmentURL: String?
    public var sourceURL: String?
    public var createdAt: Date
    public var processedAt: Date?
    public var userId: String
    
    public init(
        id: String = UUID().uuidString,
        content: String,
        type: InboxItemType = .text,
        status: InboxItemStatus = .unprocessed,
        lifeArea: LifeArea? = nil,
        suggestedPriority: Priority? = nil,
        aiSummary: String? = nil,
        aiSuggestedAction: String? = nil,
        attachmentURL: String? = nil,
        sourceURL: String? = nil,
        createdAt: Date = Date(),
        processedAt: Date? = nil,
        userId: String = ""
    ) {
        self.id = id
        self.content = content
        self.type = type
        self.status = status
        self.lifeArea = lifeArea
        self.suggestedPriority = suggestedPriority
        self.aiSummary = aiSummary
        self.aiSuggestedAction = aiSuggestedAction
        self.attachmentURL = attachmentURL
        self.sourceURL = sourceURL
        self.createdAt = createdAt
        self.processedAt = processedAt
        self.userId = userId
    }
}
