import SwiftUI
import LookAfterCore
import LookAfterAI
import LookAfterData
import LookAfterFeatures

// MARK: - 🧠 AI Memory & Semantic Search View

struct AIMemoryView: View {
    @ObservedObject var modulesVM: LifeModulesViewModel
    @State private var searchText = ""
    
    var body: some View {
        ZStack {
            PremiumBackground()
            
            VStack(spacing: DesignSystem.spacingMD) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(DesignSystem.accentPrimary)
                    
                    TextField("Semantic search over your life...", text: $searchText)
                        .font(.system(size: 15, design: .default))
                        .foregroundColor(DesignSystem.textPrimary)
                        .onChange(of: searchText) { _, newValue in
                            modulesVM.performSemanticSearch(query: newValue)
                        }
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = ""; modulesVM.performSemanticSearch(query: "") }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(DesignSystem.textMuted)
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.radiusMD)
                        .fill(DesignSystem.backgroundElevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.radiusMD)
                                .stroke(DesignSystem.accentPrimary.opacity(0.3), lineWidth: 1)
                        )
                )
                .padding(.horizontal)
                
                // Results or All Memory entries
                ScrollView {
                    LazyVStack(spacing: DesignSystem.spacingSM) {
                        if searchText.isEmpty {
                            if modulesVM.memoryEntries.isEmpty {
                                EmptyStateView(
                                    icon: "brain",
                                    title: "No AI Memories Yet",
                                    subtitle: "\(UserFacingCopy.productName) automatically indexes your daily reflections, tasks, and notes into on-device semantic memory."
                                )
                                .padding(.top, 40)
                            } else {
                                Text("Your On-Device Semantic Memory")
                                    .font(.system(size: 14, weight: .bold, design: .default))
                                    .foregroundColor(DesignSystem.textMuted)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                ForEach(modulesVM.memoryEntries) { entry in
                                    MemoryCardView(entry: entry, score: nil) {
                                        HapticManager.notification(.warning)
                                        modulesVM.deleteMemoryEntry(entry)
                                    }
                                }
                            }
                        } else {
                            Text("Semantic Vector Matches")
                                .font(.system(size: 14, weight: .bold, design: .default))
                                .foregroundColor(DesignSystem.accentPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            ForEach(modulesVM.searchResults, id: \.entry.id) { item in
                                MemoryCardView(entry: item.entry, score: item.score) {
                                    HapticManager.notification(.warning)
                                    modulesVM.deleteMemoryEntry(item.entry)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("AI Memory")
            .keyboardDismissToolbar()
        }
    }
}

struct MemoryCardView: View {
    let entry: MemoryEntry
    let score: Double?
    var onRemove: (() -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let area = entry.lifeArea {
                    Label(area.rawValue, systemImage: area.icon)
                        .font(.system(size: 11, weight: .bold, design: .default))
                        .foregroundColor(DesignSystem.textMuted)
                }
                
                Spacer()
                
                if let score = score {
                    Text("\(Int(score * 100))% match")
                        .font(.system(size: 10, weight: .bold, design: .default))
                        .foregroundColor(DesignSystem.success)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(DesignSystem.success.opacity(0.15)))
                }
                
                if let onRemove {
                    Button(action: onRemove) {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(DesignSystem.error)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove memory")
                }
            }
            
            Text(entry.content)
                .font(.system(size: 14, weight: .regular, design: .default))
                .foregroundColor(DesignSystem.textPrimary)
            
            Text(entry.createdAt.relativeTimeString)
                .font(.system(size: 10, weight: .medium, design: .default))
                .foregroundColor(DesignSystem.textMuted)
        }
        .elevatedSurface()
        .contextMenu {
            if let onRemove {
                Button(role: .destructive, action: onRemove) {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - 💳 Finance & Bills View

struct FinanceBillsView: View {
    @ObservedObject var modulesVM: LifeModulesViewModel
    @AppStorage("appCurrencySymbol") private var currencySymbol = "₹"
    
    @State private var showAddBill = false
    @State private var selectedSegment = 0
    
    private let segments = ["Overdue", "Upcoming", "Subscriptions"]
    
    var body: some View {
        ZStack {
            PremiumBackground()
            
            VStack(spacing: 0) {
                // Header summary card
                HStack(spacing: DesignSystem.spacingLG) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Upcoming Bills")
                            .font(.system(size: 13, weight: .medium, design: .default))
                            .foregroundColor(DesignSystem.textMuted)
                        
                        let unpaidTotal = modulesVM.bills.filter { !$0.isPaid }.reduce(0) { $0 + $1.amount }
                        Text(CurrencyFormatter.format(unpaidTotal))
                            .font(.system(size: 28, weight: .bold, design: .default))
                            .foregroundColor(DesignSystem.textPrimary)
                    }
                    
                    Spacer()
                    
                    Button(action: { showAddBill = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(DesignSystem.textMuted)
                    }
                }
                .elevatedSurface()
                .padding()
                
                // Segment picker
                Picker("Bill Category", selection: $selectedSegment) {
                    ForEach(0..<segments.count, id: \.self) { index in
                        Text(segments[index]).tag(index)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
                
                let displayedBills = billsForSegment(selectedSegment)
                
                if displayedBills.isEmpty {
                    EmptyStateView(
                        icon: "indianrupeesign.circle.fill",
                        title: emptyTitle(for: selectedSegment),
                        subtitle: "Keep track of subscriptions, utilities, and upcoming dues.",
                        actionTitle: "Add Bill",
                        onAction: { showAddBill = true }
                    )
                } else {
                    List {
                        ForEach(displayedBills) { bill in
                            billRow(bill)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive, action: {
                                        Task { await modulesVM.deleteBill(bill); HapticManager.notification(.warning) }
                                    }, label: {
                                        Label("Delete", systemImage: "trash")
                                    })
                                }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Finance & Bills")
        }
        .sheet(isPresented: $showAddBill) {
            AddBillSheet(modulesVM: modulesVM, currencySymbol: currencySymbol)
        }
    }
    
    private func billsForSegment(_ segment: Int) -> [BillItem] {
        switch segment {
        case 0: return modulesVM.overdueBills
        case 1: return modulesVM.upcomingBills
        default: return modulesVM.subscriptionBills
        }
    }
    
    private func emptyTitle(for segment: Int) -> String {
        switch segment {
        case 0: return "No Overdue Bills"
        case 1: return "No Upcoming Bills"
        default: return "No Subscriptions"
        }
    }
    
    @ViewBuilder
    private func billRow(_ bill: BillItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(bill.title)
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .foregroundColor(DesignSystem.textPrimary)
                
                HStack(spacing: 4) {
                    Text("Due \(bill.dueDate.shortDateString)")
                    Text("•")
                    Text(bill.category)
                    if bill.isRecurring {
                        Text("•")
                        Text(bill.recurringFrequency)
                    }
                }
                .font(.system(size: 12, weight: .medium, design: .default))
                .foregroundColor(bill.isOverdue ? DesignSystem.error : DesignSystem.textMuted)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(CurrencyFormatter.format(bill.amount))
                    .font(.system(size: 15, weight: .bold, design: .default))
                    .foregroundColor(DesignSystem.textPrimary)
                
                Button(action: { Task { await modulesVM.toggleBillPaid(bill); HapticManager.impact(.light) } }) {
                    Text(bill.isPaid ? "Paid ✓" : "Mark Paid")
                        .font(.system(size: 11, weight: .bold, design: .default))
                        .foregroundColor(bill.isPaid ? DesignSystem.success : DesignSystem.accentPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill((bill.isPaid ? DesignSystem.success : DesignSystem.accentPrimary).opacity(0.15)))
                }
                
                Button(action: {
                    Task { await modulesVM.deleteBill(bill); HapticManager.notification(.warning) }
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(DesignSystem.error)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove bill")
            }
        }
        .elevatedSurface()
        .contextMenu {
            Button(role: .destructive, action: {
                Task { await modulesVM.deleteBill(bill); HapticManager.notification(.warning) }
            }, label: {
                Label("Remove", systemImage: "trash")
            })
        }
    }
}

struct AddBillSheet: View {
    @ObservedObject var modulesVM: LifeModulesViewModel
    let currencySymbol: String
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var title = ""
    @State private var amount = ""
    @State private var category = "Subscriptions"
    @State private var dueDate = Date().adding(days: 7)
    @State private var isRecurring = true
    @State private var recurringFrequency = "Monthly"
    @State private var isSaving = false
    
    private let frequencies = ["Weekly", "Monthly", "Quarterly", "Yearly"]
    
    var body: some View {
        NavigationStack {
            PremiumForm {
                Section("Bill Details") {
                    TextField("Title (e.g. iCloud, Electricity)", text: $title)
                    TextField("Amount (\(currencySymbol))", text: $amount)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Picker("Category", selection: $category) {
                        Text("Subscriptions").tag("Subscriptions")
                        Text("Utilities").tag("Utilities")
                        Text("Credit Card").tag("Credit Card")
                        Text("Rent").tag("Rent")
                        Text("Other").tag("Other")
                    }
                    DatePicker("Due Date", selection: $dueDate, displayedComponents: .date)
                }
                
                Section("Recurring") {
                    Toggle("Recurring Bill", isOn: $isRecurring)
                    if isRecurring {
                        Picker("Frequency", selection: $recurringFrequency) {
                            ForEach(frequencies, id: \.self) { freq in
                                Text(freq).tag(freq)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Bill")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: saveBill) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || amount.isEmpty || isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .keyboardDismissToolbar(label: "Done")
        }
    }
    
    private func saveBill() {
        guard let amt = Double(amount), !title.isEmpty else { return }
        isSaving = true
        HapticManager.impact(.medium)
        Task {
            await modulesVM.addBill(
                title: title,
                amount: amt,
                dueDate: dueDate,
                category: category,
                isRecurring: isRecurring,
                recurringFrequency: isRecurring ? recurringFrequency : "None"
            )
            HapticManager.notification(.success)
            isSaving = false
            dismiss()
        }
    }
}

// MARK: - 💧 Hydration & Nutrition View

struct HydrationNutritionView: View {
    @ObservedObject var modulesVM: LifeModulesViewModel
    
    var body: some View {
        ZStack {
            PremiumBackground()
            
            VStack(spacing: DesignSystem.spacingLG) {
                // Water intake progress
                VStack(spacing: 8) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 40))
                        .foregroundColor(DesignSystem.textMuted)
                    
                    Text("\(Int(modulesVM.totalWaterTodayMl)) / 2500 ml")
                        .font(.dsTitle())
                        .foregroundColor(DesignSystem.textPrimary)
                    
                    Text("Today's Hydration Target")
                        .font(.dsCaption())
                        .foregroundColor(DesignSystem.textMuted)
                    
                    ProgressBarView(
                        progress: min(modulesVM.totalWaterTodayMl / 2500.0, 1.0),
                        height: 8
                    )
                    .padding(.horizontal)
                }
                .elevatedSurface()
                .padding()
                
                // Quick log buttons
                HStack(spacing: DesignSystem.spacingMD) {
                    Button("+ 250ml Water") { modulesVM.logWater(amountMl: 250) }
                        .buttonStyle(PremiumPrimaryButtonStyle())
                    
                    Button("+ 500ml Water") { modulesVM.logWater(amountMl: 500) }
                        .buttonStyle(PremiumPrimaryButtonStyle())
                }
                
                if !modulesVM.waterLogs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TODAY'S LOG")
                            .font(.system(size: 11, weight: .bold, design: .default))
                            .foregroundColor(DesignSystem.textMuted)
                            .padding(.horizontal)
                        
                        List {
                            ForEach(modulesVM.waterLogs.reversed()) { log in
                                HStack {
                                    Text("+\(Int(log.amountMl)) ml")
                                        .font(.system(size: 14, weight: .medium, design: .default))
                                    Spacer()
                                    Text(log.loggedAt.formatted(date: .omitted, time: .shortened))
                                        .font(.system(size: 12, design: .default))
                                        .foregroundColor(DesignSystem.textMuted)
                                    Button(action: {
                                        HapticManager.notification(.warning)
                                        modulesVM.removeWaterLog(log)
                                    }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(DesignSystem.error)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .listRowBackground(Color.clear)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive, action: {
                                        HapticManager.notification(.warning)
                                        modulesVM.removeWaterLog(log)
                                    }, label: {
                                        Label("Remove", systemImage: "trash")
                                    })
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .frame(maxHeight: 220)
                    }
                }
                
                Spacer()
            }
            .navigationTitle("Hydration & Nutrition")
        }
    }
}

// MARK: - 🛒 Shopping & Inventory View

struct ShoppingInventoryView: View {
    @ObservedObject var modulesVM: LifeModulesViewModel
    @State private var newItemName = ""
    @State private var showAddSheet = false
    @FocusState private var isQuickAddFocused: Bool
    
    var body: some View {
        ZStack {
            PremiumBackground()
            
            VStack {
                HStack {
                    TextField("Add item...", text: $newItemName)
                        .font(.system(size: 15, design: .default))
                        .foregroundColor(DesignSystem.textPrimary)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: DesignSystem.radiusMD).fill(DesignSystem.backgroundElevated))
                        .focused($isQuickAddFocused)
                        .submitLabel(.done)
                        .onSubmit { submitQuickAdd() }
                    
                    Button(action: submitQuickAdd) {
                        if modulesVM.isAddingShoppingItem {
                            ProgressView()
                                .frame(width: 28, height: 28)
                        } else {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(DesignSystem.textMuted)
                        }
                    }
                    .disabled(modulesVM.isAddingShoppingItem || newItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Add item")
                }
                .padding()
                .onAppear { isQuickAddFocused = true }

                if let message = modulesVM.shoppingSuccessMessage {
                    Text(message)
                        .font(.system(size: 12, weight: .medium, design: .default))
                        .foregroundColor(DesignSystem.success)
                        .padding(.horizontal)
                }

                if let error = modulesVM.error {
                    Text(error)
                        .font(.system(size: 12, weight: .medium, design: .default))
                        .foregroundColor(DesignSystem.error)
                        .padding(.horizontal)
                }
                
                if modulesVM.shoppingItems.isEmpty {
                    EmptyStateView(
                        icon: "cart.fill",
                        title: "Shopping List Empty",
                        subtitle: "Add items to your shopping and inventory list.",
                        actionTitle: "Create Item",
                        onAction: { showAddSheet = true }
                    )
                    .padding(.top, 40)
                } else {
                    List {
                        ForEach(modulesVM.shoppingItems) { item in
                            HStack {
                                Button(action: { Task { await modulesVM.toggleShoppingPurchased(item); HapticManager.impact(.light) } }) {
                                    Image(systemName: item.isPurchased ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 20))
                                        .foregroundColor(item.isPurchased ? DesignSystem.success : DesignSystem.textMuted)
                                }
                                
                                Text(item.name)
                                    .font(.system(size: 15, weight: .medium, design: .default))
                                    .foregroundColor(DesignSystem.textPrimary)
                                    .strikethrough(item.isPurchased)
                                
                                Spacer()
                                
                                if item.isEssential {
                                    Text("Essential")
                                        .font(.system(size: 10, weight: .bold, design: .default))
                                        .foregroundColor(DesignSystem.warning)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(DesignSystem.warning.opacity(0.15)))
                                }
                                
                                Button(action: {
                                    HapticManager.notification(.warning)
                                    Task { await modulesVM.deleteShoppingItem(item) }
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(DesignSystem.error)
                                }
                                .buttonStyle(.plain)
                            }
                            .elevatedSurface()
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive, action: {
                                    Task { await modulesVM.deleteShoppingItem(item); HapticManager.notification(.warning) }
                                }, label: {
                                    Label("Remove", systemImage: "trash")
                                })
                            }
                            .contextMenu {
                                Button(role: .destructive, action: {
                                    Task { await modulesVM.deleteShoppingItem(item); HapticManager.notification(.warning) }
                                }, label: {
                                    Label("Remove", systemImage: "trash")
                                })
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Shopping & Inventory")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showAddSheet = true }) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create shopping item")
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddShoppingItemSheet(modulesVM: modulesVM)
            }
            .keyboardDismissToolbar(label: "Add", onDone: submitQuickAdd)
        }
    }

    private func submitQuickAdd() {
        let name = newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !modulesVM.isAddingShoppingItem else { return }
        Task { @MainActor in
            let success = await modulesVM.addShoppingItem(name: name, category: "General")
            if success {
                newItemName = ""
                isQuickAddFocused = false
                KeyboardDismiss.dismiss()
                HapticManager.notification(.success)
            }
        }
    }
}

struct AddShoppingItemSheet: View {
    @ObservedObject var modulesVM: LifeModulesViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var category = "General"
    @State private var quantity = 1
    @State private var isEssential = false

    private let categories = ["General", "Groceries", "Household", "Electronics", "Personal Care"]

    var body: some View {
        NavigationStack {
            PremiumForm {
                Section("Item") {
                    TextField("Name (e.g. Milk, Paper towels)", text: $name)
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { value in
                            Text(value).tag(value)
                        }
                    }
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...99)
                    Toggle("Essential", isOn: $isEssential)
                }

                if let error = modulesVM.error {
                    Section {
                        Text(error)
                            .font(.system(size: 13, design: .default))
                            .foregroundColor(DesignSystem.error)
                    }
                }
            }
            .navigationTitle("New Item")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(modulesVM.isAddingShoppingItem)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: createItem) {
                        if modulesVM.isAddingShoppingItem {
                            ProgressView()
                        } else {
                            Text("Create")
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || modulesVM.isAddingShoppingItem)
                }
            }
            .interactiveDismissDisabled(modulesVM.isAddingShoppingItem)
            .keyboardDismissToolbar(label: "Done")
        }
    }

    private func createItem() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !modulesVM.isAddingShoppingItem else { return }
        HapticManager.impact(.medium)
        Task { @MainActor in
            let success = await modulesVM.addShoppingItem(
                name: trimmed,
                category: category,
                quantity: quantity,
                isEssential: isEssential
            )
            if success {
                HapticManager.notification(.success)
                dismiss()
            }
        }
    }
}

// MARK: - 👥 Relationships & Touchpoints View

#if os(iOS)
import ContactsUI
#endif

struct RelationshipsView: View {
    @ObservedObject var modulesVM: LifeModulesViewModel
    @State private var draftedMessage: String? = nil
    @State private var selectedContact: RelationshipContact? = nil
    @State private var showManualAdd = false
    @State private var showContactPicker = false
    
    // Manual add fields
    @State private var newName = ""
    @State private var newPhone = ""
    @State private var newRelationship = "Friend"
    
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        ZStack {
            PremiumBackground()
            
            VStack(spacing: 0) {
                // Action Header
                HStack(spacing: 12) {
                    #if os(iOS)
                    Button(action: { showContactPicker = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.crop.circle.badge.plus")
                            Text("Import iPhone Contact")
                        }
                        .font(.system(size: 13, weight: .bold, design: .default))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(DesignSystem.accentPrimary))
                    }
                    #endif
                    
                    Button(action: { showManualAdd = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                            Text("Add Manually")
                        }
                        .font(.system(size: 13, weight: .bold, design: .default))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(DesignSystem.backgroundElevated))
                    }
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)
                
                if modulesVM.contacts.isEmpty {
                    EmptyStateView(
                        icon: "person.2.fill",
                        title: "No Contacts Yet",
                        subtitle: "Import from iPhone or add people you want to stay in touch with."
                    )
                    .padding(.top, 40)
                } else {
                    List {
                        ForEach(modulesVM.contacts) { contact in
                            contactRow(contact)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive, action: {
                                        Task { await modulesVM.deleteContact(contact); HapticManager.notification(.warning) }
                                    }, label: {
                                        Label("Remove", systemImage: "trash")
                                    })
                                }
                                .contextMenu {
                                    Button(role: .destructive, action: {
                                        Task { await modulesVM.deleteContact(contact); HapticManager.notification(.warning) }
                                    }, label: {
                                        Label("Remove", systemImage: "trash")
                                    })
                                }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Relationships & Social Butler")
            #if os(iOS)
            .sheet(isPresented: $showContactPicker) {
                ContactPickerViewController { name, phone in
                    let contact = RelationshipContact(name: name, phoneNumber: phone, relationship: "Friend", userId: "user")
                    Task { await modulesVM.addContact(contact) }
                }
            }
            #endif
            .sheet(isPresented: $showManualAdd) {
                NavigationStack {
                    PremiumForm {
                        Section("Contact Details") {
                            TextField("Name", text: $newName)
                            TextField("Phone Number", text: $newPhone)
                                #if os(iOS)
                                .keyboardType(.phonePad)
                                #endif
                            Picker("Relationship", selection: $newRelationship) {
                                Text("Friend").tag("Friend")
                                Text("Family").tag("Family")
                                Text("Partner").tag("Partner")
                                Text("Colleague").tag("Colleague")
                            }
                        }
                    }
                    .navigationTitle("New Contact")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showManualAdd = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                let contact = RelationshipContact(name: newName, phoneNumber: newPhone, relationship: newRelationship, userId: "user")
                                Task { await modulesVM.addContact(contact) }
                                newName = ""
                                newPhone = ""
                                showManualAdd = false
                            }
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
                .presentationDetents([.medium])
                .keyboardDismissToolbar(label: "Done")
            }
            .sheet(item: $selectedContact) { contact in
                VStack(spacing: 20) {
                    Text("Reach Out to \(contact.name)")
                        .font(.system(size: 20, weight: .bold, design: .default))
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AI Suggested Check-In:")
                            .font(.system(size: 11, weight: .bold, design: .default))
                            .foregroundColor(DesignSystem.textMuted)
                        
                        Text(draftedMessage ?? "Hey \(contact.name)! Thinking of you today, hope all is well!")
                            .font(.system(size: 14, design: .default))
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(DesignSystem.backgroundElevated))
                    }
                    
                    // Action Buttons (WhatsApp, Text, Call)
                    VStack(spacing: 12) {
                        let cleanPhone = contact.phoneNumber.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                        let encodedDraft = (draftedMessage ?? "").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        
                        // WhatsApp
                        Button(action: {
                            if let url = URL(string: "https://wa.me/\(cleanPhone)?text=\(encodedDraft)") {
                                openURL(url)
                            }
                        }) {
                            HStack {
                                Image(systemName: "message.circle.fill")
                                Text("WhatsApp Message")
                            }
                            .font(.system(size: 16, weight: .bold, design: .default))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(DesignSystem.backgroundSecondary))
                        }
                        
                        // Text (SMS)
                        Button(action: {
                            if let url = URL(string: "sms:\(cleanPhone)&body=\(encodedDraft)") {
                                openURL(url)
                            }
                        }) {
                            HStack {
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                Text("SMS / Text Message")
                            }
                            .font(.system(size: 16, weight: .bold, design: .default))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(DesignSystem.backgroundSecondary))
                        }
                        
                        // Call
                        Button(action: {
                            if let url = URL(string: "tel:\(cleanPhone)") {
                                openURL(url)
                            }
                        }) {
                            HStack {
                                Image(systemName: "phone.fill")
                                Text("Phone Call")
                            }
                            .font(.system(size: 16, weight: .bold, design: .default))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(DesignSystem.backgroundSecondary))
                        }
                    }
                    
                    Button("Mark as Contacted Today") {
                        Task { await modulesVM.logContacted(contact) }
                        selectedContact = nil
                    }
                    .font(.system(size: 13, weight: .medium, design: .default))
                    .foregroundColor(DesignSystem.textMuted)
                    .padding(.top, 4)
                }
                .padding(24)
                .presentationDetents([.large, .medium])
            }
        }
    }
    
    @ViewBuilder
    private func contactRow(_ contact: RelationshipContact) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(contact.name)
                        .font(.system(size: 16, weight: .bold, design: .default))
                        .foregroundColor(DesignSystem.textPrimary)
                    
                    if !contact.phoneNumber.isEmpty {
                        Text("📱 \(contact.phoneNumber) • \(contact.relationship)")
                            .font(.system(size: 12, weight: .medium, design: .default))
                            .foregroundColor(DesignSystem.textMuted)
                    } else {
                        Text("\(contact.relationship) • Notes: \(contact.notes)")
                            .font(.system(size: 12, weight: .medium, design: .default))
                            .foregroundColor(DesignSystem.textMuted)
                    }
                }
                
                Spacer()
                
                Button(action: {
                    Task { await modulesVM.deleteContact(contact); HapticManager.notification(.warning) }
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(DesignSystem.error)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove contact")
            }
            
            Button(action: {
                let glm = GLMService.shared
                let aiTone = UserDefaults.standard.string(forKey: "aiCoachTone")
                let daysSince = contact.lastContactedAt.map {
                    max(1, Calendar.current.dateComponents([.day], from: $0, to: Date()).day ?? 14)
                }
                let prompt = LookAfterPrompts.socialCheckInPrompt(
                    contactName: contact.name,
                    relationshipType: contact.relationship,
                    aiTone: aiTone,
                    daysSinceContact: daysSince
                )
                Task {
                    if let draft = try? await glm.complete(
                        prompt: prompt,
                        systemPrompt: LookAfterPrompts.socialCheckInSystem,
                        tier: .economy
                    ) {
                        draftedMessage = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        draftedMessage = "Hey \(contact.name)! Thinking of you today, hope all is well!"
                    }
                    selectedContact = contact
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "paperplane.fill")
                    Text("Reach Out")
                }
                .font(.system(size: 12, weight: .bold, design: .default))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Capsule().fill(DesignSystem.accentPrimary))
            }
            .buttonStyle(.plain)
        }
        .elevatedSurface()
    }
}

#if os(iOS)
/// UIKit Contact Picker Controller Wrapper for SwiftUI
struct ContactPickerViewController: UIViewControllerRepresentable {
    var onSelect: (String, String) -> Void
    
    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }
    
    class Coordinator: NSObject, CNContactPickerDelegate {
        var onSelect: (String, String) -> Void
        
        init(onSelect: @escaping (String, String) -> Void) {
            self.onSelect = onSelect
        }
        
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let fullName = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
            let phone = contact.phoneNumbers.first?.value.stringValue ?? ""
            onSelect(fullName.isEmpty ? "New Contact" : fullName, phone)
        }
    }
}
#endif

// MARK: - ✍️ Reflection & Journaling View

struct ReflectionJournalView: View {
    @ObservedObject var modulesVM: LifeModulesViewModel
    @ObservedObject var tasksVM: TasksViewModel
    
    @State private var entryText = ""
    @State private var calibrationBadge: String? = nil
    @State private var isProcessingAI = false
    @StateObject private var speechManager = SpeechRecognitionManager()
    
    var completedToday: [LifeTask] { tasksVM.completedToday }
    var inProgressToday: [LifeTask] { tasksVM.tasks.filter { $0.status == .inProgress } }
    var unstartedToday: [LifeTask] { tasksVM.tasks.filter { $0.status == .pending } }
    
    var body: some View {
        ZStack {
            PremiumBackground()

            ScrollView {
                VStack(spacing: DesignSystem.spacingLG) {
                    journalWritingSection

                    DisclosureGroup("Today's tasks") {
                        todaysTasksBreakdown
                            .padding(.top, DesignSystem.spacingSM)
                    }
                    .font(.dsCaption(weight: .semibold))
                    .foregroundColor(DesignSystem.textSecondary)
                    .tint(DesignSystem.accentPrimary)
                    .padding(.horizontal, DesignSystem.screenHorizontal)

                    if !modulesVM.journalEntries.isEmpty {
                        VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
                            Text("Past reflections")
                                .font(.dsCaption(weight: .semibold))
                                .foregroundColor(DesignSystem.textMuted)
                                .padding(.horizontal, DesignSystem.screenHorizontal)
                            ForEach(modulesVM.journalEntries.prefix(5)) { entry in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.createdAt.shortDateString)
                                        .font(.dsMetadata(weight: .semibold))
                                        .foregroundColor(DesignSystem.accentPrimary)
                                    Text(entry.content)
                                        .font(.dsSecondary())
                                        .foregroundColor(DesignSystem.textPrimary)
                                        .lineLimit(4)
                                }
                                .padding(DesignSystem.spacingMD)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                                        .fill(DesignSystem.backgroundSecondary)
                                )
                                .padding(.horizontal, DesignSystem.screenHorizontal)
                            }
                        }
                    }
                }
                .padding(.top, DesignSystem.spacingMD)
                .padding(.bottom, DesignSystem.spacingXL)
            }
        }
        .keyboardDismissToolbar(label: "Done")
    }

    private var journalWritingSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingMD) {
            Text("Reflection")
                .font(.dsLargeTitle())
                .foregroundColor(DesignSystem.textPrimary)
                .padding(.horizontal, DesignSystem.screenHorizontal)

            VStack(alignment: .leading, spacing: DesignSystem.spacingMD) {
                Text("What went well? What was hard? The AI uses this to calibrate tomorrow.")
                    .font(.dsSecondary())
                    .foregroundColor(DesignSystem.textSecondary)

                ZStack(alignment: .bottomTrailing) {
                    TextField("Write freely…", text: $entryText, axis: .vertical)
                        .lineLimit(6...14)
                        .font(.dsBody())
                        .foregroundColor(DesignSystem.textPrimary)
                        .padding(DesignSystem.spacingMD)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.radiusLG, style: .continuous)
                                .fill(DesignSystem.backgroundSecondary)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.radiusLG, style: .continuous)
                                .stroke(DesignSystem.border, lineWidth: 1)
                        )

                    VoiceCaptureView(speechManager: speechManager, text: $entryText)
                        .padding(DesignSystem.spacingSM)
                }

                if let calibration = calibrationBadge {
                    Text("AI calibrated: \(calibration)")
                        .font(.dsCaption())
                        .foregroundColor(DesignSystem.textMuted)
                }

                PremiumPrimaryButton("Save reflection") {
                    submitReflection()
                }
                .disabled(entryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessingAI)
            }
            .padding(DesignSystem.cardPaddingMin)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.radiusLG, style: .continuous)
                    .fill(DesignSystem.backgroundSecondary.opacity(0.5))
            )
            .padding(.horizontal, DesignSystem.screenHorizontal)
        }
    }

    @ViewBuilder
    private var todaysTasksBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            if completedToday.isEmpty && inProgressToday.isEmpty && unstartedToday.isEmpty {
                Text("No tasks scheduled for today yet.")
                    .font(.dsCaption())
                    .foregroundColor(DesignSystem.textMuted)
            } else {
                taskGroup(title: "Completed", tasks: completedToday, icon: "checkmark.circle.fill", color: DesignSystem.success)
                taskGroup(title: "In progress", tasks: inProgressToday, icon: "play.circle.fill", color: DesignSystem.textSecondary)
                taskGroup(title: "Not started", tasks: unstartedToday, icon: "circle", color: DesignSystem.textMuted)
            }
        }
    }

    private func taskGroup(title: String, tasks: [LifeTask], icon: String, color: Color) -> some View {
        Group {
            if !tasks.isEmpty {
                Text(title.uppercased())
                    .font(.dsMetadata(weight: .bold))
                    .foregroundColor(DesignSystem.textMuted)
                ForEach(tasks) { task in
                    HStack {
                        Image(systemName: icon)
                            .foregroundColor(color)
                        Text(task.title)
                            .font(.dsSecondary())
                            .foregroundColor(DesignSystem.textPrimary)
                    }
                }
            }
        }
    }

    private func submitReflection() {
        guard !entryText.isEmpty else { return }
        let text = entryText
        entryText = ""
        KeyboardDismiss.dismiss()
        isProcessingAI = true

        Task {
            await modulesVM.addJournalEntry(content: text, mood: "Reflective", gratitudes: [])

            let glm = GLMService.shared
            let taskSummaryContext = """
            TODAY'S TASKS CONTEXT:
            Completed: \(completedToday.map(\.title).joined(separator: ", "))
            In-Progress: \(inProgressToday.map(\.title).joined(separator: ", "))
            Unstarted: \(unstartedToday.map(\.title).joined(separator: ", "))

            USER REFLECTION:
            \(text)
            """
            let prompt = LookAfterPrompts.journalFeedbackAnalysisPrompt(journalText: taskSummaryContext)

            if let calibration = try? await glm.complete(
                prompt: prompt,
                systemPrompt: LookAfterPrompts.structuredOutputSystem,
                tier: .economy
            ) {
                await MainActor.run {
                    calibrationBadge = calibration.trimmingCharacters(in: .whitespacesAndNewlines)
                    UserCalibrationStore.append(
                        summary: calibrationBadge ?? "",
                        source: .journal,
                        rawInput: text
                    )
                    isProcessingAI = false
                    HapticManager.notification(.success)
                }
            } else {
                await MainActor.run { isProcessingAI = false }
            }
        }
    }
}
