import Foundation

// MARK: - Finance & Bills

public struct BillItem: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var amount: Double
    public var dueDate: Date
    public var category: String           // "Utilities", "Subscriptions", "Rent", "Credit Card"
    public var isPaid: Bool
    public var isRecurring: Bool
    public var recurringFrequency: String // "Monthly", "Yearly", "Weekly"
    public var paidAt: Date?
    public var autoPayEnabled: Bool
    public var notes: String
    public var userId: String
    
    public init(
        id: String = UUID().uuidString,
        title: String,
        amount: Double,
        dueDate: Date,
        category: String = "Subscriptions",
        isPaid: Bool = false,
        isRecurring: Bool = true,
        recurringFrequency: String = "Monthly",
        paidAt: Date? = nil,
        autoPayEnabled: Bool = false,
        notes: String = "",
        userId: String = ""
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.dueDate = dueDate
        self.category = category
        self.isPaid = isPaid
        self.isRecurring = isRecurring
        self.recurringFrequency = recurringFrequency
        self.paidAt = paidAt
        self.autoPayEnabled = autoPayEnabled
        self.notes = notes
        self.userId = userId
    }
    
    public var isOverdue: Bool {
        !isPaid && dueDate < Date()
    }
}

// MARK: - Shopping & Inventory

public struct ShoppingItem: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var category: String          // "Groceries", "Household", "Electronics", "Personal Care"
    public var quantity: Int
    public var isPurchased: Bool
    public var isEssential: Bool
    public var estimatedCost: Double?
    public var addedAt: Date
    public var purchasedAt: Date?
    public var storeName: String?
    public var userId: String
    
    public init(
        id: String = UUID().uuidString,
        name: String,
        category: String = "Groceries",
        quantity: Int = 1,
        isPurchased: Bool = false,
        isEssential: Bool = false,
        estimatedCost: Double? = nil,
        addedAt: Date = Date(),
        purchasedAt: Date? = nil,
        storeName: String? = nil,
        userId: String = ""
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.quantity = quantity
        self.isPurchased = isPurchased
        self.isEssential = isEssential
        self.estimatedCost = estimatedCost
        self.addedAt = addedAt
        self.purchasedAt = purchasedAt
        self.storeName = storeName
        self.userId = userId
    }
}

// MARK: - Hydration & Nutrition

public struct HydrationLog: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var amountMl: Double
    public var loggedAt: Date
    public var beverageType: String      // "Water", "Electrolytes", "Tea", "Coffee"
    public var userId: String
    
    public init(
        id: String = UUID().uuidString,
        amountMl: Double = 250,
        loggedAt: Date = Date(),
        beverageType: String = "Water",
        userId: String = ""
    ) {
        self.id = id
        self.amountMl = amountMl
        self.loggedAt = loggedAt
        self.beverageType = beverageType
        self.userId = userId
    }
}

// MARK: - Relationships

public struct RelationshipContact: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var phoneNumber: String
    public var relationship: String       // "Friend", "Family", "Partner", "Colleague"
    public var birthday: Date?
    public var lastContactedAt: Date?
    public var targetFrequencyDays: Int    // e.g., 7 days (contact once a week)
    public var notes: String               // Gift ideas, important memory notes
    public var importantDates: [String: Date]
    public var userId: String
    
    public init(
        id: String = UUID().uuidString,
        name: String,
        phoneNumber: String = "",
        relationship: String = "Friend",
        birthday: Date? = nil,
        lastContactedAt: Date? = nil,
        targetFrequencyDays: Int = 14,
        notes: String = "",
        importantDates: [String: Date] = [:],
        userId: String = ""
    ) {
        self.id = id
        self.name = name
        self.phoneNumber = phoneNumber
        self.relationship = relationship
        self.birthday = birthday
        self.lastContactedAt = lastContactedAt
        self.targetFrequencyDays = targetFrequencyDays
        self.notes = notes
        self.importantDates = importantDates
        self.userId = userId
    }
    
    public var needsContact: Bool {
        guard let last = lastContactedAt else { return true }
        let days = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
        return days >= targetFrequencyDays
    }
}

// MARK: - Travel Planner

public struct PackingItem: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var category: String          // "Clothing", "Toiletries", "Tech", "Documents"
    public var isPacked: Bool
    
    public init(id: String = UUID().uuidString, name: String, category: String = "General", isPacked: Bool = false) {
        self.id = id
        self.name = name
        self.category = category
        self.isPacked = isPacked
    }
}

public struct TravelTrip: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var destination: String
    public var startDate: Date
    public var endDate: Date
    public var packingList: [PackingItem]
    public var notes: String
    public var flightsOrBookings: String
    public var userId: String
    
    public init(
        id: String = UUID().uuidString,
        destination: String,
        startDate: Date,
        endDate: Date,
        packingList: [PackingItem] = [],
        notes: String = "",
        flightsOrBookings: String = "",
        userId: String = ""
    ) {
        self.id = id
        self.destination = destination
        self.startDate = startDate
        self.endDate = endDate
        self.packingList = packingList
        self.notes = notes
        self.flightsOrBookings = flightsOrBookings
        self.userId = userId
    }
    
    public var isUpcoming: Bool {
        startDate > Date()
    }
}

// MARK: - Reflection & Journaling

public struct JournalEntry: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var content: String
    public var mood: String              // "Great", "Calm", "Anxious", "Low Energy", "Hyperfocused"
    public var gratitudes: [String]
    public var aiReflectionInsight: String?
    public var createdAt: Date
    public var userId: String
    
    public init(
        id: String = UUID().uuidString,
        title: String = "",
        content: String,
        mood: String = "Calm",
        gratitudes: [String] = [],
        aiReflectionInsight: String? = nil,
        createdAt: Date = Date(),
        userId: String = ""
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.mood = mood
        self.gratitudes = gratitudes
        self.aiReflectionInsight = aiReflectionInsight
        self.createdAt = createdAt
        self.userId = userId
    }
}

// MARK: - Learning & Knowledge

public struct KnowledgeNote: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var content: String
    public var source: String             // Book title, article URL, podcast
    public var tags: [String]
    public var keyTakeaways: [String]
    public var lifeArea: LifeArea
    public var createdAt: Date
    public var userId: String
    
    public init(
        id: String = UUID().uuidString,
        title: String,
        content: String,
        source: String = "",
        tags: [String] = [],
        keyTakeaways: [String] = [],
        lifeArea: LifeArea = .learning,
        createdAt: Date = Date(),
        userId: String = ""
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.source = source
        self.tags = tags
        self.keyTakeaways = keyTakeaways
        self.lifeArea = lifeArea
        self.createdAt = createdAt
        self.userId = userId
    }
}

// MARK: - Calendar Intelligence

public struct CalendarEventItem: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var isAllDay: Bool
    public var location: String?
    public var energyCost: EnergyLevel
    public var isDeepWorkTime: Bool
    
    public init(
        id: String = UUID().uuidString,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false,
        location: String? = nil,
        energyCost: EnergyLevel = .moderate,
        isDeepWorkTime: Bool = false
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.location = location
        self.energyCost = energyCost
        self.isDeepWorkTime = isDeepWorkTime
    }
}
