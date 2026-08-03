import Foundation

// MARK: - Medication Management

public struct Medication: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var dosage: String
    public var scheduledTime: Date
    public var isTaken: Bool
    public var lastTakenAt: Date?
    public var adherenceLog: [Date]
    
    public init(
        id: String = UUID().uuidString,
        name: String,
        dosage: String,
        scheduledTime: Date,
        isTaken: Bool = false,
        lastTakenAt: Date? = nil,
        adherenceLog: [Date] = []
    ) {
        self.id = id
        self.name = name
        self.dosage = dosage
        self.scheduledTime = scheduledTime
        self.isTaken = isTaken
        self.lastTakenAt = lastTakenAt
        self.adherenceLog = adherenceLog
    }
}

// MARK: - Creativity Workspace

public struct CreativeProject: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var medium: String
    public var status: String
    public var lastOpened: Date
    public var progress: Double
    public var dayCount: Int?
    public var deadline: Date?
    public var parentTaskId: String?
    public var lifeArea: LifeArea?
    public var milestoneTaskIds: [String]?

    enum CodingKeys: String, CodingKey {
        case id, title, medium, status, lastOpened, progress
        case dayCount, deadline, parentTaskId, lifeArea, milestoneTaskIds
    }

    public init(
        id: String = UUID().uuidString,
        title: String,
        medium: String,
        status: String = "Ideation",
        lastOpened: Date = Date(),
        progress: Double = 0.0,
        dayCount: Int? = nil,
        deadline: Date? = nil,
        parentTaskId: String? = nil,
        lifeArea: LifeArea? = nil,
        milestoneTaskIds: [String]? = nil
    ) {
        self.id = id
        self.title = title
        self.medium = medium
        self.status = status
        self.lastOpened = lastOpened
        self.progress = progress
        self.dayCount = dayCount
        self.deadline = deadline
        self.parentTaskId = parentTaskId
        self.lifeArea = lifeArea
        self.milestoneTaskIds = milestoneTaskIds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        medium = try container.decode(String.self, forKey: .medium)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "Ideation"
        lastOpened = try container.decodeIfPresent(Date.self, forKey: .lastOpened) ?? Date()
        progress = try container.decodeIfPresent(Double.self, forKey: .progress) ?? 0.0
        dayCount = try container.decodeIfPresent(Int.self, forKey: .dayCount)
        deadline = try container.decodeIfPresent(Date.self, forKey: .deadline)
        parentTaskId = try container.decodeIfPresent(String.self, forKey: .parentTaskId)
        lifeArea = try container.decodeIfPresent(LifeArea.self, forKey: .lifeArea)
        milestoneTaskIds = try container.decodeIfPresent([String].self, forKey: .milestoneTaskIds)
    }

    public static let statusOptions = ["Ideation", "In Progress", "Review", "Complete"]
}
