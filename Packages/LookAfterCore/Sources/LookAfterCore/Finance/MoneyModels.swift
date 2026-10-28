import Foundation

public enum SpendKind: String, Codable, Sendable, Equatable {
    case need
    case extra
}

public enum FixedCostRole: String, Codable, Sendable, Equatable {
    case obligation
    case optional
}

/// Sections inside the fixed-cost list. Existing bill categories map onto these.
public enum FixedExpenseSection: String, CaseIterable, Sendable, Equatable, Hashable {
    case rent = "Rent"
    case utilities = "Utility bills"
    case petrol = "Petrol"
    case emi = "EMI"
    case subscriptions = "Subscriptions"
    case insurance = "Insurance"
    case creditCard = "Credit Card"
    case other = "Other"

    /// Sections a person can add into. Credit card stays visible when a bill already uses it.
    public static let addChoices: [FixedExpenseSection] = [
        .rent, .utilities, .petrol, .emi, .creditCard, .subscriptions, .insurance, .other
    ]

    public static let emiKinds = ["Home loan", "Car", "Personal loan", "Education", "Other"]

    public var isOptionalSpend: Bool { self == .subscriptions }

    public static func matching(_ category: String) -> FixedExpenseSection {
        let value = category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.contains("rent") { return .rent }
        if value.contains("petrol") || value.contains("fuel") { return .petrol }
        if value.contains("emi") || value.contains("loan") { return .emi }
        if value.contains("util") || value.contains("electric") || value.contains("broadband") || value.contains("wifi") {
            return .utilities
        }
        if value.contains("subscr") || value.contains("stream") { return .subscriptions }
        if value.contains("insur") { return .insurance }
        if value.contains("credit") { return .creditCard }
        return .other
    }
}

public struct MoneyPlan: Identifiable, Codable, Sendable, Equatable, Hashable {
    public var id: String
    public var monthlySalary: Double
    public var paydayDay: Int
    public var savingsPercent: Double
    public var goalName: String
    public var largeExtraThreshold: Double
    public var currencyCode: String
    public var updatedAt: Date
    public var userId: String
    /// Optional bill amounts captured at the start of this pay cycle.
    public var priorOptionalAmounts: [String: Double]
    public var baselineCycleStart: Date?
    /// A chosen spending cap for the pay cycle. Empty means the suggested limit is used.
    public var spendingLimit: Double?

    public init(
        id: String = UUID().uuidString,
        monthlySalary: Double,
        paydayDay: Int = 1,
        savingsPercent: Double = 10,
        goalName: String = "Savings",
        largeExtraThreshold: Double = 2_000,
        currencyCode: String = "INR",
        updatedAt: Date = Date(),
        userId: String = "",
        priorOptionalAmounts: [String: Double] = [:],
        baselineCycleStart: Date? = nil,
        spendingLimit: Double? = nil
    ) {
        self.id = id
        self.monthlySalary = monthlySalary
        self.paydayDay = min(28, max(1, paydayDay))
        self.savingsPercent = savingsPercent
        self.goalName = goalName
        self.largeExtraThreshold = largeExtraThreshold
        self.currencyCode = currencyCode
        self.updatedAt = updatedAt
        self.userId = userId
        self.priorOptionalAmounts = priorOptionalAmounts
        self.baselineCycleStart = baselineCycleStart
        self.spendingLimit = spendingLimit
    }

    private enum CodingKeys: String, CodingKey {
        case id, monthlySalary, paydayDay, savingsPercent, goalName, largeExtraThreshold
        case currencyCode, updatedAt, userId, priorOptionalAmounts, baselineCycleStart, spendingLimit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        monthlySalary = try container.decode(Double.self, forKey: .monthlySalary)
        paydayDay = min(28, max(1, try container.decodeIfPresent(Int.self, forKey: .paydayDay) ?? 1))
        savingsPercent = try container.decodeIfPresent(Double.self, forKey: .savingsPercent) ?? 10
        goalName = try container.decodeIfPresent(String.self, forKey: .goalName) ?? "Savings"
        largeExtraThreshold = try container.decodeIfPresent(Double.self, forKey: .largeExtraThreshold) ?? 2_000
        currencyCode = try container.decodeIfPresent(String.self, forKey: .currencyCode) ?? "INR"
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        userId = try container.decodeIfPresent(String.self, forKey: .userId) ?? ""
        priorOptionalAmounts = try container.decodeIfPresent([String: Double].self, forKey: .priorOptionalAmounts) ?? [:]
        baselineCycleStart = try container.decodeIfPresent(Date.self, forKey: .baselineCycleStart)
        spendingLimit = try container.decodeIfPresent(Double.self, forKey: .spendingLimit)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(monthlySalary, forKey: .monthlySalary)
        try container.encode(paydayDay, forKey: .paydayDay)
        try container.encode(savingsPercent, forKey: .savingsPercent)
        try container.encode(goalName, forKey: .goalName)
        try container.encode(largeExtraThreshold, forKey: .largeExtraThreshold)
        try container.encode(currencyCode, forKey: .currencyCode)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(userId, forKey: .userId)
        try container.encode(priorOptionalAmounts, forKey: .priorOptionalAmounts)
        try container.encodeIfPresent(baselineCycleStart, forKey: .baselineCycleStart)
        try container.encodeIfPresent(spendingLimit, forKey: .spendingLimit)
    }
}

public enum MoneyProjectionPace: String, Equatable, Sendable {
    case onTrack
    case room
    case over
}

/// This cycle's spending cap, what is already spent, and where today's pace lands by payday.
public struct MoneyMonthProjection: Equatable, Sendable {
    public var limit: Double
    public var suggestedLimit: Double
    public var usesOwnLimit: Bool
    public var spent: Double
    public var remaining: Double
    public var projectedSpend: Double
    public var dailyAllowance: Double
    public var dayNumber: Int
    public var dayCount: Int
    public var daysLeft: Int
    public var pace: MoneyProjectionPace
    public var sentence: String
}

public struct DailyExpense: Identifiable, Codable, Sendable, Equatable, Hashable {
    public var id: String
    public var amount: Double
    public var kind: SpendKind
    public var note: String
    public var occurredOn: Date
    public var userId: String

    public init(
        id: String = UUID().uuidString,
        amount: Double,
        kind: SpendKind,
        note: String = "",
        occurredOn: Date,
        userId: String = ""
    ) {
        self.id = id
        self.amount = amount
        self.kind = kind
        self.note = note
        self.occurredOn = occurredOn
        self.userId = userId
    }
}

/// Last confirmed Need or Extra for a note. On device only.
public struct SpendKindMemory: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String { noteKey }
    public var noteKey: String
    public var kind: SpendKind

    public init(noteKey: String, kind: SpendKind) {
        self.noteKey = noteKey
        self.kind = kind
    }
}

public enum MoneyCaptureDraft: Equatable, Sendable {
    case salary(amount: Double, payday: Int)
    case fixedCost(title: String, amount: Double, dueDay: Int)
    case spend(amount: Double, note: String)
}

public enum MoneySuggestion: Equatable, Sendable {
    case dueBeforePayday(title: String, amount: Double)
    case savingsShortfall(amount: Double, goalName: String)
    case optionalFixedHigh(title: String, amount: Double)
    case fixedShareHigh(share: Double, largestTitle: String, largestAmount: Double)
    case nothingLeftUnpaid(title: String)
    case onTrack(goalName: String, kept: Double)
}

public struct MoneyCycleSnapshot: Equatable, Sendable {
    public var salary: Double
    public var fixedTotal: Double
    public var savingsTarget: Double
    public var savingsKept: Double
    public var needSpent: Double
    public var extraSpent: Double
    public var safeToSpend: Double
    public var extraLeftThisWeek: Double
    public var suggestion: MoneySuggestion?
    /// The card stays hidden after a short night. The numbers above stay visible.
    public var cardHiddenForShortSleep: Bool
    /// Set on payday morning: what the previous cycle kept for the goal.
    public var previousCycleKept: Double?
    public var cycleStart: Date
    public var cycleEnd: Date
}

/// One slice of this month's pay. The amounts come from the engine, not the model.
public struct MoneySplitLine: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    public var amount: Double

    public init(id: String, title: String, detail: String, amount: Double) {
        self.id = id
        self.title = title
        self.detail = detail
        self.amount = amount
    }
}

public struct MoneySplit: Equatable, Sendable {
    public var salary: Double
    public var lines: [MoneySplitLine]
    public var sentence: String
}

/// Savings rate, emergency fund, and where today sits in the pay cycle. Amounts are calculated, not guessed by the model.
public struct MoneyPlanGuide: Equatable, Sendable {
    public var recommendedSavingsPercent: Double
    public var recommendedMonthlySave: Double
    public var emergencyTarget: Double
    public var emergencyUsesEstimate: Bool
    public var monthsToFund: Int
    public var savingsReason: String
    public var cycleStart: Date
    public var cycleEnd: Date
    public var dayNumber: Int
    public var dayCount: Int
    public var daysLeft: Int
    public var sentence: String
}
