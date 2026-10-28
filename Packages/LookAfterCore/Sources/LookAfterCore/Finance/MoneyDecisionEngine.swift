import Foundation

public enum MoneyDecisionEngine {
    public static let shortSleepHours = 6.0
    public static let optionalShareLimit = 0.10
    public static let fixedShareLimit = 0.50

    public static func role(for bill: BillItem) -> FixedCostRole {
        let category = bill.category.lowercased()
        if FixedExpenseSection.matching(bill.category).isOptionalSpend || category.contains("stream") {
            return .optional
        }
        return .obligation
    }

    public static func requiresLargeExtraConfirmation(amount: Double, kind: SpendKind, plan: MoneyPlan) -> Bool {
        kind == .extra && amount >= plan.largeExtraThreshold && plan.largeExtraThreshold > 0
    }

    public static func normalizedNote(_ note: String) -> String {
        note.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func rememberedKind(note: String, memory: [SpendKindMemory]) -> SpendKind? {
        let key = normalizedNote(note)
        guard !key.isEmpty else { return nil }
        return memory.first { $0.noteKey == key }?.kind
    }

    public static func remember(note: String, kind: SpendKind, memory: [SpendKindMemory]) -> [SpendKindMemory] {
        let key = normalizedNote(note)
        guard !key.isEmpty else { return memory }
        var next = memory.filter { $0.noteKey != key }
        next.append(SpendKindMemory(noteKey: key, kind: kind))
        return next
    }

    /// Keyword hint used when the note has never been confirmed.
    public static func classifyNote(_ note: String) -> SpendKind {
        let key = normalizedNote(note)
        let extraWords = ["swiggy", "zomato", "jacket", "luxury", "cinema", "shopping", "amazon", "uber eats", "apple", "flipkart"]
        if extraWords.contains(where: { key.contains($0) }) { return .extra }
        return .need
    }

    public static func evaluate(
        plan: MoneyPlan,
        bills: [BillItem],
        expenses: [DailyExpense],
        priorOptionalAmounts: [String: Double] = [:],
        now: Date,
        calendar: Calendar,
        sleepHours: Double? = nil
    ) -> MoneyCycleSnapshot? {
        guard plan.monthlySalary > 0 else { return nil }
        let cycle = cycle(containing: now, payday: plan.paydayDay, calendar: calendar)
        let inCycle = expenses.filter { expense in
            let day = calendar.startOfDay(for: expense.occurredOn)
            return day >= cycle.start && day < cycle.end
        }
        let needSpent = inCycle.filter { $0.kind == .need }.reduce(0) { $0 + $1.amount }
        let extraSpent = inCycle.filter { $0.kind == .extra }.reduce(0) { $0 + $1.amount }
        let due = bills.filter { bill in
            let day = calendar.startOfDay(for: bill.dueDate)
            return day >= cycle.start && day < cycle.end
        }
        let fixedTotal = budgetedBills(bills, paydayDay: plan.paydayDay, payCycle: cycle, calendar: calendar)
            .reduce(0) { $0 + $1.amount }
        let savingsTarget = plan.monthlySalary * plan.savingsPercent / 100
        let spent = needSpent + extraSpent
        let eaten = max(0, spent - max(0, plan.monthlySalary - fixedTotal - savingsTarget))
        let savingsKept = max(0, savingsTarget - eaten)
        let remaining = max(0, plan.monthlySalary - fixedTotal - savingsTarget - spent)
        let today = calendar.startOfDay(for: now)
        let daysLeft = max(1, calendar.dateComponents([.day], from: today, to: cycle.end).day ?? 1)
        let weekEnd = calendar.dateInterval(of: .weekOfYear, for: today)?.end ?? cycle.end
        let weekLimit = min(cycle.end, weekEnd)
        let weekDays = max(1, calendar.dateComponents([.day], from: today, to: weekLimit).day ?? 1)
        let daily = remaining / Double(daysLeft)
        let extraLeftThisWeek = min(remaining, daily * Double(min(weekDays, daysLeft)))

        let suggestion = pickSuggestion(
            plan: plan,
            due: due,
            expenses: inCycle,
            extraSpent: extraSpent,
            needSpent: needSpent,
            fixedTotal: fixedTotal,
            savingsTarget: savingsTarget,
            savingsKept: savingsKept,
            remaining: remaining,
            cycle: cycle,
            now: today,
            calendar: calendar,
            priorOptionalAmounts: priorOptionalAmounts
        )
        let hideCard = (sleepHours ?? 99) < shortSleepHours
        let close: Double? = calendar.component(.day, from: today) == plan.paydayDay
            ? kept(
                plan: plan,
                bills: bills,
                expenses: expenses,
                cycle: previousCycle(endingAt: today, payday: plan.paydayDay, calendar: calendar),
                calendar: calendar
            )
            : nil
        return MoneyCycleSnapshot(
            salary: plan.monthlySalary,
            fixedTotal: fixedTotal,
            savingsTarget: savingsTarget,
            savingsKept: savingsKept,
            needSpent: needSpent,
            extraSpent: extraSpent,
            safeToSpend: remaining,
            extraLeftThisWeek: extraLeftThisWeek,
            suggestion: hideCard ? nil : suggestion,
            cardHiddenForShortSleep: hideCard,
            previousCycleKept: close,
            cycleStart: cycle.start,
            cycleEnd: cycle.end
        )
    }

    /// Splits this cycle's pay into save, home and dues, everyday bills, essentials, shopping and luxury, and a cushion.
    /// Fixed lines use the bills already entered. Essentials, luxury, and the cushion share what is left.
    public static func split(
        plan: MoneyPlan,
        bills: [BillItem],
        now: Date,
        calendar: Calendar
    ) -> MoneySplit? {
        guard plan.monthlySalary > 0 else { return nil }
        let cycle = cycle(containing: now, payday: plan.paydayDay, calendar: calendar)
        let due = budgetedBills(bills, paydayDay: plan.paydayDay, payCycle: cycle, calendar: calendar)
        func total(_ sections: Set<FixedExpenseSection>) -> Double {
            due.filter { sections.contains(FixedExpenseSection.matching($0.category)) }
                .reduce(0) { $0 + $1.amount }
                .rounded()
        }
        let save = (plan.monthlySalary * plan.savingsPercent / 100).rounded()
        let home = total([.rent, .emi, .insurance])
        let card = total([.creditCard])
        let everyday = total([.utilities, .petrol, .creditCard, .other])
        let subscriptions = total([.subscriptions])
        let pool = plan.monthlySalary - save - home - everyday
        var essentials = 0.0
        var luxury = 0.0
        var cushion = 0.0
        if pool > 0 {
            essentials = (pool * 0.60).rounded()
            luxury = max(subscriptions, (pool * 0.25).rounded())
            cushion = pool - essentials - luxury
            if cushion < 0 {
                essentials = max(0, essentials + cushion)
                cushion = pool - essentials - luxury
            }
            if cushion < 0 {
                luxury = max(0, pool)
                essentials = 0
                cushion = 0
            }
            let drift = plan.monthlySalary - (save + home + everyday + essentials + luxury + cushion)
            cushion += drift
            if cushion < 0 {
                essentials = max(0, essentials + cushion)
                cushion = 0
            }
        } else {
            luxury = subscriptions
        }
        let lines = [
            MoneySplitLine(id: "save", title: "Save", detail: "For \(plan.goalName)", amount: save),
            MoneySplitLine(id: "home", title: "Home and dues", detail: "Rent, EMI, and insurance", amount: home),
            MoneySplitLine(
                id: "bills",
                title: "Everyday bills",
                detail: card > 0 ? "Utilities, petrol, and the card you pay next month" : "Utilities and petrol",
                amount: everyday
            ),
            MoneySplitLine(id: "essentials", title: "Essentials", detail: "Food, travel, and household", amount: essentials),
            MoneySplitLine(id: "luxury", title: "Shopping and luxury", detail: "Subscriptions and extras", amount: luxury),
            MoneySplitLine(id: "cushion", title: "Cushion", detail: "Left for a surprise", amount: max(0, cushion))
        ]
        return MoneySplit(salary: plan.monthlySalary, lines: lines, sentence: splitSentence(lines, goal: plan.goalName, short: pool <= 0))
    }

    /// Recommends a savings rate from the room left after fixed costs, plus a three-month emergency fund and where today sits in the cycle.
    public static func guide(
        plan: MoneyPlan,
        bills: [BillItem],
        now: Date,
        calendar: Calendar
    ) -> MoneyPlanGuide? {
        guard plan.monthlySalary > 0 else { return nil }
        let payCycle = cycle(containing: now, payday: plan.paydayDay, calendar: calendar)
        let fixedBills = budgetedBills(bills, paydayDay: plan.paydayDay, payCycle: payCycle, calendar: calendar)
        let fixed = fixedBills.reduce(0) { $0 + $1.amount }
        let roomShare = max(0, (plan.monthlySalary - fixed) / plan.monthlySalary)
        let rawPercent: Double
        if roomShare >= 0.50 {
            rawPercent = 20
        } else if roomShare >= 0.30 {
            rawPercent = 15
        } else if roomShare >= 0.10 {
            rawPercent = 10
        } else {
            rawPercent = (roomShare * 100).rounded(.down)
        }
        let monthly = (plan.monthlySalary * rawPercent / 100).rounded()
        let committed = fixedBills.filter {
            let section = FixedExpenseSection.matching($0.category)
            return section != .subscriptions
        }.reduce(0) { $0 + $1.amount }
        let usesEstimate = committed <= 0
        let emergency = (usesEstimate ? plan.monthlySalary * 0.40 : committed) * 3
        let emergencyRounded = emergency.rounded()
        let months = monthly > 0 ? Int(ceil(emergencyRounded / monthly)) : 0
        let today = calendar.startOfDay(for: now)
        let dayCount = max(1, calendar.dateComponents([.day], from: payCycle.start, to: payCycle.end).day ?? 1)
        let elapsed = max(0, calendar.dateComponents([.day], from: payCycle.start, to: today).day ?? 0)
        let dayNumber = min(dayCount, elapsed + 1)
        let daysLeft = max(0, calendar.dateComponents([.day], from: today, to: payCycle.end).day ?? 0)
        let estimateNote = usesEstimate ? " Add rent and bills to base the emergency fund on your real costs." : ""
        let reason: String
        if rawPercent >= 20 {
            reason = "After fixed costs there is room, so \(plain(rawPercent))% (\(plain(monthly)) a month) fits."
        } else if rawPercent >= 10 {
            reason = "Fixed costs take a large share, so \(plain(rawPercent))% (\(plain(monthly)) a month) is the recommended start."
        } else {
            reason = "Fixed costs use almost all of this pay, so \(plain(rawPercent))% is what is left to save."
        }
        let sentence = "Day \(dayNumber) of \(dayCount), \(daysLeft) days left. \(reason) An emergency fund of \(plain(emergencyRounded)) is about \(months) months at that pace.\(estimateNote)"
        return MoneyPlanGuide(
            recommendedSavingsPercent: rawPercent,
            recommendedMonthlySave: monthly,
            emergencyTarget: emergencyRounded,
            emergencyUsesEstimate: usesEstimate,
            monthsToFund: months,
            savingsReason: reason,
            cycleStart: payCycle.start,
            cycleEnd: payCycle.end,
            dayNumber: dayNumber,
            dayCount: dayCount,
            daysLeft: daysLeft,
            sentence: sentence
        )
    }

    /// Projects variable spending against this cycle's limit. The suggested limit is pay minus savings and fixed bills. A stored limit replaces it.
    public static func projection(
        plan: MoneyPlan,
        bills: [BillItem],
        expenses: [DailyExpense],
        now: Date,
        calendar: Calendar
    ) -> MoneyMonthProjection? {
        guard plan.monthlySalary > 0 else { return nil }
        let payCycle = cycle(containing: now, payday: plan.paydayDay, calendar: calendar)
        let fixed = budgetedBills(bills, paydayDay: plan.paydayDay, payCycle: payCycle, calendar: calendar)
            .reduce(0) { $0 + $1.amount }
        let savings = plan.monthlySalary * plan.savingsPercent / 100
        let suggested = max(0, (plan.monthlySalary - fixed - savings).rounded())
        let own = plan.spendingLimit.flatMap { $0 > 0 ? $0.rounded() : nil }
        let limit = own ?? suggested
        let today = calendar.startOfDay(for: now)
        let spent = expenses.filter { expense in
            let day = calendar.startOfDay(for: expense.occurredOn)
            return day >= payCycle.start && day < payCycle.end
        }.reduce(0) { $0 + $1.amount }.rounded()
        let dayCount = max(1, calendar.dateComponents([.day], from: payCycle.start, to: payCycle.end).day ?? 1)
        let elapsed = max(0, calendar.dateComponents([.day], from: payCycle.start, to: today).day ?? 0)
        let dayNumber = min(dayCount, elapsed + 1)
        let daysLeft = max(1, calendar.dateComponents([.day], from: today, to: payCycle.end).day ?? 1)
        let projected = ((spent / Double(dayNumber)) * Double(dayCount)).rounded()
        let remaining = max(0, (limit - spent).rounded())
        let daily = (remaining / Double(daysLeft)).rounded()
        let pace: MoneyProjectionPace
        if limit > 0, projected > limit {
            pace = .over
        } else if limit > 0, dayNumber > 3, spent > 0, projected <= (limit * 0.90).rounded() {
            pace = .room
        } else {
            pace = .onTrack
        }
        let sentence = projectionSentence(
            limit: limit,
            suggested: suggested,
            usesOwnLimit: own != nil,
            spent: spent,
            projected: projected,
            daily: daily,
            dayNumber: dayNumber,
            pace: pace
        )
        return MoneyMonthProjection(
            limit: limit,
            suggestedLimit: suggested,
            usesOwnLimit: own != nil,
            spent: spent,
            remaining: remaining,
            projectedSpend: projected,
            dailyAllowance: daily,
            dayNumber: dayNumber,
            dayCount: dayCount,
            daysLeft: daysLeft,
            pace: pace,
            sentence: sentence
        )
    }

    private static func projectionSentence(
        limit: Double,
        suggested: Double,
        usesOwnLimit: Bool,
        spent: Double,
        projected: Double,
        daily: Double,
        dayNumber: Int,
        pace: MoneyProjectionPace
    ) -> String {
        let source = usesOwnLimit ? "Your spending limit is \(plain(limit))." : "Suggested spending limit is \(plain(limit))."
        switch pace {
        case .over:
            return "\(source) \(plain(spent)) is already spent. At this pace the month ends at \(plain(projected)). Holding to \(plain(daily)) a day stays inside the limit."
        case .room:
            return "\(source) \(plain(spent)) is spent, and this pace ends the month at \(plain(projected)). About \(plain(daily)) a day still fits."
        case .onTrack:
            let early = dayNumber <= 3 ? " It is early in the month, so this is only a first look." : ""
            return "\(source) \(plain(spent)) is spent. At this pace the month ends at \(plain(projected)). About \(plain(daily)) a day keeps it there.\(early)"
        }
    }

    private static func splitSentence(_ lines: [MoneySplitLine], goal: String, short: Bool) -> String {
        func amount(_ id: String) -> String {
            plain(lines.first { $0.id == id }?.amount ?? 0)
        }
        if short {
            return "Save, home, and everyday bills already use this pay. Shopping and luxury shows the subscriptions already entered."
        }
        return "Keep \(amount("save")) for \(goal). Home and dues \(amount("home")). Everyday bills \(amount("bills")). Essentials \(amount("essentials")). Shopping and luxury \(amount("luxury")). Cushion \(amount("cushion"))."
    }

    public static func sentence(for suggestion: MoneySuggestion) -> String {
        switch suggestion {
        case .dueBeforePayday(let title, let amount):
            return "\(title) (\(plain(amount))) is due before payday. The cash is not in yet."
        case .savingsShortfall(let amount, let goalName):
            return "Extras are ahead of \(goalName) by \(plain(amount))."
        case .optionalFixedHigh(let title, let amount):
            return "\(title) (\(plain(amount))) is the largest optional fixed cost."
        case .fixedShareHigh(let share, let largestTitle, _):
            return "Fixed costs are \(Int((share * 100).rounded()))% of pay. \(largestTitle) is the largest line."
        case .nothingLeftUnpaid(let title):
            return "Nothing is left to spend while \(title) is still unpaid."
        case .onTrack(let goalName, let kept):
            return "On track to keep \(plain(kept)) for \(goalName)."
        }
    }

    public static func parseCapture(_ text: String) -> MoneyCaptureDraft? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        guard let amount = firstAmount(in: lower) else { return nil }
        if lower.contains("salary") || lower.contains("i get") || lower.contains("i earn") || lower.contains("paid ") {
            let day = dayNumber(in: lower) ?? 1
            return .salary(amount: amount, payday: min(28, max(1, day)))
        }
        if lower.contains("rent") || lower.contains("petrol") || lower.contains("fuel")
            || lower.contains("emi") || lower.contains("loan") || lower.contains("bill")
            || lower.contains("subscription") || lower.contains("electric") || lower.contains("utilit") {
            let day = dayNumber(in: lower) ?? 1
            let title = fixedTitle(from: lower)
            return .fixedCost(title: title, amount: amount, dueDay: min(28, max(1, day)))
        }
        let note = trimmed
            .replacingOccurrences(of: amountText(in: trimmed) ?? "", with: "")
            .replacingOccurrences(of: " on ", with: " ", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .spend(amount: amount, note: note.isEmpty ? "Spend" : note)
    }

    // MARK: - Cycle

    public static func cycle(containing now: Date, payday: Int, calendar: Calendar) -> (start: Date, end: Date) {
        let day = calendar.startOfDay(for: now)
        let paydayDay = min(28, max(1, payday))
        let parts = calendar.dateComponents([.year, .month], from: day)
        let thisMonth = date(year: parts.year ?? 2026, month: parts.month ?? 1, day: paydayDay, calendar: calendar)
        if day >= thisMonth {
            let next = calendar.date(byAdding: .month, value: 1, to: thisMonth) ?? thisMonth
            return (thisMonth, next)
        }
        let previous = calendar.date(byAdding: .month, value: -1, to: thisMonth) ?? thisMonth
        return (previous, thisMonth)
    }

    private static func previousCycle(endingAt paydayDate: Date, payday: Int, calendar: Calendar) -> (start: Date, end: Date) {
        let end = calendar.startOfDay(for: paydayDate)
        let start = calendar.date(byAdding: .month, value: -1, to: end) ?? end
        _ = payday
        return (start, end)
    }

    /// A card payment counts in the month the spending happened, which is the cycle before the due date.
    /// The month you actually pay does not subtract it again.
    public enum CreditCardBudgetTiming: Equatable, Sendable {
        case setAsideThisMonth
        case paidFromLastMonth
    }

    public static func creditCardBudgetTiming(
        for bill: BillItem,
        paydayDay: Int,
        now: Date,
        calendar: Calendar
    ) -> CreditCardBudgetTiming? {
        guard FixedExpenseSection.matching(bill.category) == .creditCard else { return nil }
        let current = cycle(containing: now, payday: paydayDay, calendar: calendar)
        let due = calendar.startOfDay(for: bill.dueDate)
        let next = cycle(containing: current.end, payday: paydayDay, calendar: calendar)
        if due >= next.start && due < next.end { return .setAsideThisMonth }
        if due >= current.start && due < current.end { return .paidFromLastMonth }
        return nil
    }

    static func budgetedBills(
        _ bills: [BillItem],
        paydayDay: Int,
        payCycle: (start: Date, end: Date),
        calendar: Calendar
    ) -> [BillItem] {
        let next = cycle(containing: payCycle.end, payday: paydayDay, calendar: calendar)
        return bills.filter { bill in
            let day = calendar.startOfDay(for: bill.dueDate)
            if FixedExpenseSection.matching(bill.category) == .creditCard {
                return day >= next.start && day < next.end
            }
            return day >= payCycle.start && day < payCycle.end
        }
    }

    private static func kept(
        plan: MoneyPlan,
        bills: [BillItem],
        expenses: [DailyExpense],
        cycle: (start: Date, end: Date),
        calendar: Calendar
    ) -> Double {
        let inCycle = expenses.filter { expense in
            let day = calendar.startOfDay(for: expense.occurredOn)
            return day >= cycle.start && day < cycle.end
        }
        let spent = inCycle.reduce(0) { $0 + $1.amount }
        let fixed = budgetedBills(bills, paydayDay: plan.paydayDay, payCycle: cycle, calendar: calendar)
            .reduce(0) { $0 + $1.amount }
        let target = plan.monthlySalary * plan.savingsPercent / 100
        let eaten = max(0, spent - max(0, plan.monthlySalary - fixed - target))
        return max(0, target - eaten)
    }

    private static func pickSuggestion(
        plan: MoneyPlan,
        due: [BillItem],
        expenses: [DailyExpense],
        extraSpent: Double,
        needSpent: Double,
        fixedTotal: Double,
        savingsTarget: Double,
        savingsKept: Double,
        remaining: Double,
        cycle: (start: Date, end: Date),
        now: Date,
        calendar: Calendar,
        priorOptionalAmounts: [String: Double]
    ) -> MoneySuggestion {
        let unpaid = due.filter { !$0.isPaid }
        if let early = unpaid.first(where: { bill in
            guard role(for: bill) == .obligation else { return false }
            let dueDay = calendar.startOfDay(for: bill.dueDate)
            let dueDom = calendar.component(.day, from: dueDay)
            let beforePayday = dueDom < plan.paydayDay && dueDay < cycle.end
            let soon = calendar.dateComponents([.day], from: now, to: dueDay).day ?? 99
            let extrasAfter = expenses.contains { expense in
                expense.kind == .extra && calendar.startOfDay(for: expense.occurredOn) >= dueDay
            }
            return beforePayday || (soon >= 0 && soon <= 7 && extrasAfter)
        }) {
            return .dueBeforePayday(title: early.title, amount: early.amount)
        }

        let elapsed = max(1, calendar.dateComponents([.day], from: cycle.start, to: now).day ?? 1)
        let length = max(elapsed, calendar.dateComponents([.day], from: cycle.start, to: cycle.end).day ?? elapsed)
        let projectedExtra = extraSpent * Double(length) / Double(elapsed)
        let room = plan.monthlySalary - fixedTotal - savingsTarget - needSpent
        if projectedExtra > room {
            return .savingsShortfall(amount: projectedExtra - room, goalName: plan.goalName)
        }

        let optional = due.filter { role(for: $0) == .optional }
        let optionalTotal = optional.reduce(0) { $0 + $1.amount }
        if let grown = optional.first(where: { bill in
            guard let prior = priorOptionalAmounts[bill.id] else { return false }
            return bill.amount > prior
        }) {
            return .optionalFixedHigh(title: grown.title, amount: grown.amount)
        }
        if plan.monthlySalary > 0, optionalTotal > plan.monthlySalary * optionalShareLimit, let largest = optional.max(by: { $0.amount < $1.amount }) {
            return .optionalFixedHigh(title: largest.title, amount: largest.amount)
        }

        if plan.monthlySalary > 0, fixedTotal > plan.monthlySalary * fixedShareLimit, let largest = due.max(by: { $0.amount < $1.amount }) {
            return .fixedShareHigh(share: fixedTotal / plan.monthlySalary, largestTitle: largest.title, largestAmount: largest.amount)
        }

        if remaining == 0, let unpaidBill = unpaid.first {
            return .nothingLeftUnpaid(title: unpaidBill.title)
        }

        return .onTrack(goalName: plan.goalName, kept: savingsKept)
    }

    private static func plain(_ amount: Double) -> String {
        String(format: "%.0f", amount.rounded())
    }

    private static func date(year: Int, month: Int, day: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
            ?? calendar.startOfDay(for: Date())
    }

    private static func fixedTitle(from lower: String) -> String {
        if lower.contains("rent") { return "Rent" }
        if lower.contains("petrol") || lower.contains("fuel") { return "Petrol" }
        if lower.contains("emi") || lower.contains("loan") {
            if lower.contains("home") { return "Home loan" }
            if lower.contains("car") || lower.contains("vehicle") { return "Car" }
            if lower.contains("personal") { return "Personal loan" }
            if lower.contains("educat") { return "Education" }
            return "EMI"
        }
        if lower.contains("subscription") { return "Subscription" }
        if lower.contains("electric") || lower.contains("utilit") { return "Utility bill" }
        return "Bill"
    }

    private static func firstAmount(in text: String) -> Double? {
        let pattern = #"(\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        let digits = text[range].replacingOccurrences(of: ",", with: "")
        return Double(digits)
    }

    private static func amountText(in text: String) -> String? {
        let pattern = #"(\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        return String(text[range])
    }

    private static func dayNumber(in text: String) -> Int? {
        let pattern = #"on (?:the )?(\d{1,2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[range])
    }
}
