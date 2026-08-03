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
    private let semanticStore: SemanticMemoryStore
    
    public init(
        billRepo: BillRepository? = nil,
        shoppingRepo: ShoppingRepository? = nil,
        relRepo: RelationshipRepository? = nil,
        journalRepo: JournalRepository? = nil,
        semanticStore: SemanticMemoryStore = SemanticMemoryStore()
    ) {
        self.billRepo = billRepo ?? BillRepository()
        self.shoppingRepo = shoppingRepo ?? ShoppingRepository()
        self.relRepo = relRepo ?? RelationshipRepository()
        self.journalRepo = journalRepo ?? JournalRepository()
        self.semanticStore = semanticStore
    }
    
    // MARK: - Load All Module Data
    
    public func loadAllData(userId: String) async {
        if FreshInstallGuard.isActive {
            resetInMemoryState()
            return
        }
        isLoading = true
        do {
            async let loadedBills = billRepo.getAll(for: userId)
            async let loadedShopping = shoppingRepo.getAll(for: userId)
            async let loadedRel = relRepo.getAll(for: userId)
            async let loadedJournal = journalRepo.getAll(for: userId)
            
            self.bills = try await loadedBills
            self.shoppingItems = Self.mergeShoppingItems(
                existing: self.shoppingItems,
                loaded: try await loadedShopping
            )
            self.contacts = try await loadedRel
            self.journalEntries = try await loadedJournal
            
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
    
    // MARK: - Module Actions
    
    public func addBill(
        title: String,
        amount: Double,
        dueDate: Date,
        category: String,
        isRecurring: Bool = true,
        recurringFrequency: String = "Monthly"
    ) async {
        let bill = BillItem(
            title: title,
            amount: amount,
            dueDate: dueDate,
            category: category,
            isRecurring: isRecurring,
            recurringFrequency: recurringFrequency
        )
        bills.append(bill)
        try? await billRepo.create(bill)
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
        bills.filter { !$0.isPaid && !$0.isOverdue && $0.category != "Subscriptions" && !$0.isRecurring }
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
    
    public func logWater(amountMl: Double = 250) {
        let log = HydrationLog(amountMl: amountMl)
        waterLogs.append(log)
        totalWaterTodayMl += amountMl
    }
    
    public func addContact(name: String, relationship: String, targetFrequencyDays: Int) async {
        let contact = RelationshipContact(name: name, relationship: relationship, targetFrequencyDays: targetFrequencyDays)
        contacts.append(contact)
        try? await relRepo.create(contact)
    }
    
    public func addContact(_ contact: RelationshipContact) async {
        contacts.append(contact)
        try? await relRepo.create(contact)
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
        try? await journalRepo.create(entry)
        
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
    
    public func removeWaterLog(_ log: HydrationLog) {
        guard let index = waterLogs.firstIndex(where: { $0.id == log.id }) else { return }
        totalWaterTodayMl = max(0, totalWaterTodayMl - waterLogs[index].amountMl)
        waterLogs.remove(at: index)
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
        var merged = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        for item in existing where merged[item.id] == nil {
            merged[item.id] = item
        }
        return merged.values.sorted { $0.addedAt > $1.addedAt }
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
        searchQuery = ""
        searchResults = []
        isLoading = false
        error = nil
        shoppingSuccessMessage = nil
    }
}
