import Foundation
import LookAfterCore
import LookAfterAI
import LookAfterData

/// LifeModulesViewModel — central state manager for all specialized LifeOS modules.
@MainActor
public final class LifeModulesViewModel: ObservableObject {
    
    // Modules State
    @Published public var bills: [BillItem] = []
    @Published public var shoppingItems: [ShoppingItem] = []
    @Published public var contacts: [RelationshipContact] = []
    @Published public var journalEntries: [JournalEntry] = []
    @Published public var memoryEntries: [MemoryEntry] = []
    @Published public var waterLogs: [HydrationLog] = []
    @Published public var moneyPlan: MoneyPlan?
    @Published public var dailyExpenses: [DailyExpense] = []
    @Published public var spendKindMemory: [SpendKindMemory] = []
    @Published public var pendingLargeExtra: DailyExpense?
    @Published public var decisionSentence: String = ""
    @Published public var totalWaterTodayMl: Double = 0
    @Published public var searchQuery: String = ""
    @Published public var searchResults: [(entry: MemoryEntry, score: Double)] = []
    
    @Published public var isLoading: Bool = false
    @Published public var isAddingShoppingItem: Bool = false
    @Published public var shoppingSuccessMessage: String?
    @Published public var error: String?
    
    private let billRepo: BillRepository
    private let shoppingRepo: ShoppingRepository
    private let relRepo: RelationshipRepository
    private let journalRepo: JournalRepository
    private let hydrationRepo: HydrationRepository
    private let moneyRepo: MoneyRepository
    private let semanticStore: SemanticMemoryStore

    public init(
        billRepo: BillRepository? = nil,
        shoppingRepo: ShoppingRepository? = nil,
        relRepo: RelationshipRepository? = nil,
        journalRepo: JournalRepository? = nil,
        hydrationRepo: HydrationRepository? = nil,
        moneyRepo: MoneyRepository? = nil,
        semanticStore: SemanticMemoryStore = SemanticMemoryStore()
    ) {
        self.billRepo = billRepo ?? BillRepository()
        self.shoppingRepo = shoppingRepo ?? ShoppingRepository()
        self.relRepo = relRepo ?? RelationshipRepository()
        self.journalRepo = journalRepo ?? JournalRepository()
        self.hydrationRepo = hydrationRepo ?? HydrationRepository()
        self.moneyRepo = moneyRepo ?? MoneyRepository()
        self.semanticStore = semanticStore
    }
    
    // MARK: - Load All Module Data
    
    public func loadAllData(userId: String) async {
        if FreshInstallGuard.isActive {
            resetInMemoryState()
            return
        }
        isLoading = true

        // Kick off each fetch concurrently, then await independently so one failure
        // does not discard siblings that already succeeded.
        async let billsLoad = billRepo.getAll(for: userId)
        async let shoppingLoad = shoppingRepo.getAll(for: userId)
        async let relLoad = relRepo.getAll(for: userId)
        async let journalLoad = journalRepo.getAll(for: userId)
        async let hydrationLoad = hydrationRepo.getToday(for: userId)

        var errors: [String] = []

        do {
            self.bills = try await billsLoad
        } catch {
            errors.append(error.localizedDescription)
        }
        do {
            let loaded = try await shoppingLoad
            self.shoppingItems = Self.mergeShoppingItems(existing: self.shoppingItems, loaded: loaded)
        } catch {
            errors.append(error.localizedDescription)
        }
        do {
            self.contacts = try await relLoad
        } catch {
            errors.append(error.localizedDescription)
        }
        do {
            self.journalEntries = try await journalLoad
        } catch {
            errors.append(error.localizedDescription)
        }
        do {
            self.waterLogs = try await hydrationLoad
            self.totalWaterTodayMl = self.waterLogs.reduce(0) { $0 + $1.amountMl }
        } catch {
            errors.append(error.localizedDescription)
        }
        do {
            self.moneyPlan = try await moneyRepo.loadPlan(for: userId)
            self.dailyExpenses = try await moneyRepo.loadExpenses(for: userId)
            self.spendKindMemory = moneyRepo.loadSpendKindMemory()
            refreshDecisionSentence()
        } catch {
            errors.append(error.localizedDescription)
        }

        self.error = errors.isEmpty ? nil : errors.joined(separator: "\n")
        isLoading = false
    }
    
    // MARK: - Module Actions
    
    public func addBill(
        title: String,
        amount: Double,
        dueDate: Date,
        category: String,
        isRecurring: Bool = true,
        recurringFrequency: String = "Monthly",
        notes: String = ""
    ) async {
        let bill = BillItem(
            title: title,
            amount: amount,
            dueDate: dueDate,
            category: category,
            isRecurring: isRecurring,
            recurringFrequency: recurringFrequency,
            notes: notes
        )
        bills.append(bill)
        do {
            try await billRepo.create(bill)
        } catch {
            bills.removeAll { $0.id == bill.id }
            self.error = "Couldn't add bill: \(error.localizedDescription)"
        }
    }
    
    public func toggleBillPaid(_ bill: BillItem) async {
        if let idx = bills.firstIndex(where: { $0.id == bill.id }) {
            bills[idx].isPaid.toggle()
            bills[idx].paidAt = bills[idx].isPaid ? Date() : nil
        }
        try? await billRepo.togglePaid(bill)
    }
    
    public func deleteBill(_ bill: BillItem) async {
        bills.removeAll { $0.id == bill.id }
        try? await billRepo.delete(bill)
    }
    
    public var overdueBills: [BillItem] {
        bills.filter { $0.isOverdue && !$0.isPaid }
    }
    
    public var upcomingBills: [BillItem] {
        let horizon = Calendar.current.date(byAdding: .day, value: 45, to: Date()) ?? Date()
        return bills.filter { bill in
            !bill.isPaid && !bill.isOverdue && bill.dueDate <= horizon
        }
    }
    
    public var subscriptionBills: [BillItem] {
        bills.filter { !$0.isPaid && !$0.isOverdue && ($0.category == "Subscriptions" || $0.isRecurring) }
    }
    
    public func addShoppingItem(
        name: String,
        category: String,
        quantity: Int = 1,
        isEssential: Bool = false
    ) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            error = "Enter an item name before creating."
            return false
        }
        guard !isAddingShoppingItem else { return false }

        isAddingShoppingItem = true
        error = nil
        shoppingSuccessMessage = nil

        let item = ShoppingItem(
            name: trimmed,
            category: category,
            quantity: max(quantity, 1),
            isEssential: isEssential
        )
        shoppingItems.insert(item, at: 0)

        do {
            try await shoppingRepo.create(item)
            shoppingSuccessMessage = "\"\(trimmed)\" added to your list"
            print("[ShoppingList] Created item id=\(item.id) name=\(trimmed)")
            isAddingShoppingItem = false
            return true
        } catch {
            shoppingItems.removeAll { $0.id == item.id }
            self.error = "Couldn't add item: \(error.localizedDescription)"
            print("[ShoppingList] Create failed for \(trimmed): \(error)")
            isAddingShoppingItem = false
            return false
        }
    }
    
    public func toggleShoppingPurchased(_ item: ShoppingItem) async {
        if let idx = shoppingItems.firstIndex(where: { $0.id == item.id }) {
            shoppingItems[idx].isPurchased.toggle()
        }
        try? await shoppingRepo.togglePurchased(item)
    }
    
    public func deleteShoppingItem(_ item: ShoppingItem) async {
        shoppingItems.removeAll { $0.id == item.id }
        try? await shoppingRepo.delete(item)
    }
    
    public func logWater(amountMl: Double = 250) async {
        let log = HydrationLog(amountMl: amountMl)
        waterLogs.append(log)
        totalWaterTodayMl += amountMl
        do {
            try await hydrationRepo.create(log)
        } catch {
            waterLogs.removeAll { $0.id == log.id }
            totalWaterTodayMl = max(0, totalWaterTodayMl - amountMl)
            self.error = "Couldn't log water: \(error.localizedDescription)"
        }
    }
    
    public func addContact(name: String, relationship: String, targetFrequencyDays: Int) async {
        let contact = RelationshipContact(name: name, relationship: relationship, targetFrequencyDays: targetFrequencyDays)
        await addContact(contact)
    }

    public func addContact(_ contact: RelationshipContact) async {
        contacts.append(contact)
        do {
            try await relRepo.create(contact)
        } catch {
            contacts.removeAll { $0.id == contact.id }
            self.error = "Couldn't add contact: \(error.localizedDescription)"
        }
    }
    
    public func logContacted(_ contact: RelationshipContact) async {
        if let idx = contacts.firstIndex(where: { $0.id == contact.id }) {
            contacts[idx].lastContactedAt = Date()
        }
        try? await relRepo.logContact(contact)
    }
    
    public func deleteContact(_ contact: RelationshipContact) async {
        contacts.removeAll { $0.id == contact.id }
        try? await relRepo.delete(contact)
    }
    
    public func addJournalEntry(content: String, mood: String, gratitudes: [String]) async {
        let entry = JournalEntry(content: content, mood: mood, gratitudes: gratitudes)
        journalEntries.insert(entry, at: 0)
        do {
            try await journalRepo.create(entry)
        } catch {
            journalEntries.removeAll { $0.id == entry.id }
            self.error = "Couldn't add journal entry: \(error.localizedDescription)"
            return
        }

        // Save to AI Memory
        let mem = MemoryEntry(content: content, sourceType: "journal")
        memoryEntries.append(mem)
    }
    
    public func deleteJournalEntry(_ entry: JournalEntry) async {
        journalEntries.removeAll { $0.id == entry.id }
        try? await journalRepo.delete(entry)
    }
    
    public func deleteMemoryEntry(_ entry: MemoryEntry) {
        memoryEntries.removeAll { $0.id == entry.id }
        if !searchQuery.isEmpty {
            performSemanticSearch(query: searchQuery)
        }
    }
    
    public func removeWaterLog(_ log: HydrationLog) async {
        guard let index = waterLogs.firstIndex(where: { $0.id == log.id }) else { return }
        totalWaterTodayMl = max(0, totalWaterTodayMl - waterLogs[index].amountMl)
        waterLogs.remove(at: index)
        try? await hydrationRepo.delete(log)
    }
    
    public func performSemanticSearch(query: String) {
        self.searchQuery = query
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }
        searchResults = semanticStore.search(query: query, entries: memoryEntries, limit: 10)
    }

    private static func mergeShoppingItems(existing: [ShoppingItem], loaded: [ShoppingItem]) -> [ShoppingItem] {
        var merged = Dictionary.uniquingFirstValue(loaded.map { ($0.id, $0) })
        for item in existing where merged[item.id] == nil {
            merged[item.id] = item
        }
        return merged.values.sorted { $0.addedAt > $1.addedAt }
    }

    public func moneySnapshot(
        now: Date = Date(),
        calendar: Calendar = .current,
        sleepHours: Double? = nil
    ) -> MoneyCycleSnapshot? {
        guard let moneyPlan else { return nil }
        return MoneyDecisionEngine.evaluate(
            plan: moneyPlan,
            bills: bills,
            expenses: dailyExpenses,
            priorOptionalAmounts: moneyPlan.priorOptionalAmounts,
            now: now,
            calendar: calendar,
            sleepHours: sleepHours
        )
    }

    public func moneyPlanningLine(now: Date = Date(), calendar: Calendar = .current, sleepHours: Double? = nil) -> String {
        guard let snapshot = moneySnapshot(now: now, calendar: calendar, sleepHours: sleepHours) else { return "" }
        let due = bills.first { !$0.isPaid }
        let dueText = due.map { " Due: \($0.title) \($0.amount)." } ?? ""
        return "Safe to spend \(Int(snapshot.safeToSpend.rounded())). Extras left this week \(Int(snapshot.extraLeftThisWeek.rounded())).\(dueText)"
    }

    public func saveSalary(
        amount: Double,
        payday: Int,
        goalName: String,
        userId: String,
        savingsPercent: Double? = nil,
        spendingLimit: Double? = nil,
        clearSpendingLimit: Bool = false,
        now: Date = Date()
    ) async {
        var plan = moneyPlan ?? MoneyPlan(id: userId, monthlySalary: amount, userId: userId)
        plan.monthlySalary = amount
        plan.paydayDay = payday
        plan.goalName = goalName.isEmpty ? "Savings" : goalName
        if let savingsPercent {
            plan.savingsPercent = min(100, max(0, savingsPercent))
        }
        if clearSpendingLimit {
            plan.spendingLimit = nil
        } else if let spendingLimit {
            plan.spendingLimit = spendingLimit > 0 ? spendingLimit : nil
        }
        plan.userId = userId
        plan.updatedAt = now
        if plan.id.isEmpty { plan.id = userId }
        moneyPlan = plan
        refreshDecisionSentence()
        try? await moneyRepo.savePlan(plan)
    }

    /// Returns false when a large Extra is waiting for one confirmation.
    @discardableResult
    public func logSpend(amount: Double, kind: SpendKind, note: String, userId: String, now: Date = Date()) async -> Bool {
        guard let plan = moneyPlan, amount > 0 else { return false }
        let expense = DailyExpense(amount: amount, kind: kind, note: note, occurredOn: now, userId: userId)
        if MoneyDecisionEngine.requiresLargeExtraConfirmation(amount: amount, kind: kind, plan: plan) {
            pendingLargeExtra = expense
            return false
        }
        await commit(expense)
        return true
    }

    public func confirmPendingExtra() async {
        guard let pendingLargeExtra else { return }
        self.pendingLargeExtra = nil
        await commit(pendingLargeExtra)
    }

    public func dismissPendingExtra() {
        pendingLargeExtra = nil
    }

    public func chipKind(for note: String) -> SpendKind {
        MoneyDecisionEngine.rememberedKind(note: note, memory: spendKindMemory)
            ?? MoneyDecisionEngine.classifyNote(note)
    }

    public func applyCapture(_ text: String, userId: String, now: Date = Date()) async -> MoneyCaptureDraft? {
        guard let draft = MoneyDecisionEngine.parseCapture(text) else { return nil }
        switch draft {
        case .salary(let amount, let payday):
            await saveSalary(amount: amount, payday: payday, goalName: moneyPlan?.goalName ?? "Savings", userId: userId, now: now)
        case .fixedCost(let title, let amount, let dueDay):
            var components = Calendar.current.dateComponents([.year, .month], from: now)
            components.day = dueDay
            let due = Calendar.current.date(from: components) ?? now
            let section = FixedExpenseSection.matching(title)
            await addBill(
                title: title,
                amount: amount,
                dueDate: due,
                category: section.rawValue,
                notes: section == .emi ? title : ""
            )
        case .spend(let amount, let note):
            _ = await logSpend(amount: amount, kind: chipKind(for: note), note: note, userId: userId, now: now)
        }
        return draft
    }

    public func refreshDecisionSentence(now: Date = Date(), sleepHours: Double? = nil) {
        guard let suggestion = moneySnapshot(now: now, sleepHours: sleepHours)?.suggestion else {
            decisionSentence = ""
            return
        }
        decisionSentence = MoneyDecisionEngine.sentence(for: suggestion)
    }

    public func refreshMoneyBaselines(now: Date = Date(), calendar: Calendar = .current) async {
        guard var plan = moneyPlan, plan.monthlySalary > 0 else { return }
        let start = MoneyDecisionEngine.cycle(containing: now, payday: plan.paydayDay, calendar: calendar).start
        guard plan.baselineCycleStart != start else { return }
        var prior: [String: Double] = [:]
        for bill in bills where MoneyDecisionEngine.role(for: bill) == .optional {
            prior[bill.id] = bill.amount
        }
        plan.priorOptionalAmounts = prior
        plan.baselineCycleStart = start
        moneyPlan = plan
        try? await moneyRepo.savePlan(plan)
    }

    public func refreshDecisionSentenceWithVoice(now: Date = Date(), sleepHours: Double? = nil) async {
        await refreshMoneyBaselines(now: now)
        guard let snapshot = moneySnapshot(now: now, sleepHours: sleepHours),
              let suggestion = snapshot.suggestion else {
            decisionSentence = ""
            return
        }
        decisionSentence = await MoneyPhraseService.phrase(
            suggestion,
            salary: snapshot.salary,
            fixed: snapshot.fixedTotal,
            extraSoFar: snapshot.extraSpent,
            safeToSpend: snapshot.safeToSpend
        )
    }

    public func updateSpend(_ expense: DailyExpense) async {
        guard expense.amount > 0 else { return }
        if let index = dailyExpenses.firstIndex(where: { $0.id == expense.id }) {
            dailyExpenses[index] = expense
        } else {
            dailyExpenses.append(expense)
        }
        spendKindMemory = MoneyDecisionEngine.remember(note: expense.note, kind: expense.kind, memory: spendKindMemory)
        moneyRepo.saveSpendKindMemory(spendKindMemory)
        refreshDecisionSentence(now: expense.occurredOn)
        try? await moneyRepo.saveExpense(expense)
    }

    /// Adds statement debits that are not already logged. Returns how many were added.
    /// Saves one bill per card. A statement for card 7517 does not overwrite card 4801.
    public func applyCardStatement(
        amount: Double,
        label: String = "",
        dueOn: Date? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async {
        let payday = moneyPlan?.paydayDay ?? 1
        let due = dueOn ?? MoneyDecisionEngine.cycle(containing: now, payday: payday, calendar: calendar).end
        let named = !label.isEmpty && label != "Card"
        let title = named ? "Credit card \(label)" : "Credit card"
        if let index = bills.firstIndex(where: { bill in
            guard FixedExpenseSection.matching(bill.category) == .creditCard else { return false }
            guard named else { return true }
            return (bill.title + " " + bill.notes).contains(label)
        }) {
            bills[index].amount = amount
            bills[index].dueDate = due
            bills[index].isPaid = false
            bills[index].paidAt = nil
            bills[index].title = title
            if named { bills[index].notes = label }
            try? await billRepo.save(bills[index])
            return
        }
        await addBill(
            title: title,
            amount: amount,
            dueDate: due,
            category: FixedExpenseSection.creditCard.rawValue,
            notes: named ? label : "From the card statement"
        )
    }

    public func addImportedSpends(_ lines: [StatementLine], userId: String, now: Date = Date()) async -> Int {
        let calendar = Calendar.current
        var added = 0
        for line in lines where line.direction == .moneyOut && line.amount > 0 {
            let duplicate = dailyExpenses.contains { MoneyStatementEngine.sameSpend($0, line, calendar: calendar) }
            guard !duplicate else { continue }
            let expense = DailyExpense(
                amount: line.amount,
                kind: line.kind,
                note: line.note,
                occurredOn: line.occurredOn,
                userId: userId
            )
            await commit(expense)
            added += 1
        }
        if added > 0 {
            await refreshDecisionSentenceWithVoice(now: now)
        }
        return added
    }

    public func deleteSpend(_ expense: DailyExpense) async {
        dailyExpenses.removeAll { $0.id == expense.id }
        refreshDecisionSentence(now: expense.occurredOn)
        try? await moneyRepo.deleteExpense(expense)
    }

    private func commit(_ expense: DailyExpense) async {
        dailyExpenses.append(expense)
        spendKindMemory = MoneyDecisionEngine.remember(note: expense.note, kind: expense.kind, memory: spendKindMemory)
        moneyRepo.saveSpendKindMemory(spendKindMemory)
        refreshDecisionSentence(now: expense.occurredOn)
        try? await moneyRepo.saveExpense(expense)
    }

    /// Clears all module presentation state after factory reset.
    public func resetInMemoryState() {
        bills = []
        shoppingItems = []
        contacts = []
        journalEntries = []
        memoryEntries = []
        waterLogs = []
        totalWaterTodayMl = 0
        moneyPlan = nil
        dailyExpenses = []
        spendKindMemory = []
        pendingLargeExtra = nil
        decisionSentence = ""
        searchQuery = ""
        searchResults = []
        isLoading = false
        error = nil
        shoppingSuccessMessage = nil
    }
}
