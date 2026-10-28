import SwiftUI
import UniformTypeIdentifiers
import PDFKit
import LookAfterCore
import LookAfterAI
import LookAfterData
import LookAfterFeatures

// MARK: - 🧠 AI Memory & Semantic Search View

struct AIMemoryView: View {
    @ObservedObject var modulesVM: LifeModulesViewModel
    @State private var searchText = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    
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
                            scheduleSemanticSearch(query: newValue)
                        }
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchDebounceTask?.cancel()
                            searchText = ""
                            modulesVM.performSemanticSearch(query: "")
                        }) {
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
        .onDisappear {
            searchDebounceTask?.cancel()
        }
    }

    private func scheduleSemanticSearch(query: String) {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            modulesVM.performSemanticSearch(query: query)
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
    var userId: String = ""
    var sleepHours: Double? = nil
    @AppStorage("appCurrencySymbol") private var currencySymbol = "₹"
    
    @State private var showAddBill = false
    @State private var showLogSpend = false
    @State private var showOnboarding = false
    @State private var showStatements = false
    @State private var showCardStatement = false
    @State private var statementOpensHistory = true
    @State private var editingSpend: DailyExpense?
    @State private var addSection: FixedExpenseSection = .rent
    @State private var billFilter = 0
    
    var body: some View {
        ZStack {
            PremiumBackground()
            List {
                Section {
                    MoneyPlannerHeader(
                        modulesVM: modulesVM,
                        userId: userId,
                        sleepHours: sleepHours,
                        onSetup: { showOnboarding = true },
                        onStatements: { opening in
                            statementOpensHistory = opening
                            showStatements = true
                        },
                        onCard: { showCardStatement = true },
                        billFilter: $billFilter
                    )
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))

                if groups.isEmpty {
                    Section {
                        Text(emptyTitle)
                            .font(.body)
                            .foregroundStyle(DesignSystem.textSecondary)
                        Button("Add a fixed cost") { openAdd(.rent) }
                            .font(.body.weight(.semibold))
                    }
                } else {
                    ForEach(groups, id: \.0) { section, rows in
                        Section {
                            ForEach(rows) { bill in
                                billRow(bill)
                            }
                        } header: {
                            HStack {
                                Text(section.rawValue)
                                Spacer()
                                Text(CurrencyFormatter.format(rows.reduce(0) { $0 + $1.amount }))
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isHeader)
                        }
                    }
                }

                if !cycleSpends.isEmpty {
                    Section("Spent this cycle") {
                        ForEach(cycleSpends) { expense in
                            spendRow(expense)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .navigationTitle("Finance")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Picker("Show", selection: $billFilter) {
                        Text("All").tag(0)
                        Text("Overdue").tag(1)
                        Text("Due soon").tag(2)
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("Which bills to show")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ForEach(FixedExpenseSection.addChoices, id: \.self) { section in
                            Button(section.rawValue) { openAdd(section) }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add a fixed cost")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    showLogSpend = true
                } label: {
                    Text("Log a spend")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)
                .accessibilityHint("Amount, then Need or Extra")
            }
        }
        .sheet(isPresented: $showAddBill) {
            AddBillSheet(modulesVM: modulesVM, currencySymbol: currencySymbol, section: addSection)
        }
        .sheet(isPresented: $showLogSpend) {
            LogSpendSheet(modulesVM: modulesVM, userId: userId, sleepHours: sleepHours)
        }
        .sheet(isPresented: $showOnboarding) {
            FinanceOnboardingSheet(modulesVM: modulesVM, userId: userId, sleepHours: sleepHours)
        }
        .sheet(isPresented: $showStatements) {
            StatementImportSheet(
                modulesVM: modulesVM,
                userId: userId,
                openingHistory: statementOpensHistory
            )
        }
        .sheet(isPresented: $showCardStatement) {
            StatementImportSheet(
                modulesVM: modulesVM,
                userId: userId,
                openingHistory: false,
                cardStatement: true
            )
        }
        .sheet(item: $editingSpend) { expense in
            EditSpendSheet(modulesVM: modulesVM, expense: expense, sleepHours: sleepHours)
        }
        .confirmationDialog(
            "Save this extra of \(CurrencyFormatter.format(modulesVM.pendingLargeExtra?.amount ?? 0))?",
            isPresented: largeExtraPresented,
            titleVisibility: .visible
        ) {
            Button("Save") { Task { await modulesVM.confirmPendingExtra() } }
            Button("Leave it", role: .cancel) { modulesVM.dismissPendingExtra() }
        }
    }

    private var largeExtraPresented: Binding<Bool> {
        Binding(
            get: { modulesVM.pendingLargeExtra != nil && !showLogSpend },
            set: { if !$0 { modulesVM.dismissPendingExtra() } }
        )
    }

    private var groups: [(FixedExpenseSection, [BillItem])] {
        groupedSections(for: billFilter)
    }

    private var cycleSpends: [DailyExpense] {
        guard let snapshot = modulesVM.moneySnapshot(sleepHours: sleepHours) else {
            return modulesVM.dailyExpenses.sorted { $0.occurredOn > $1.occurredOn }
        }
        return modulesVM.dailyExpenses
            .filter { $0.occurredOn >= snapshot.cycleStart && $0.occurredOn < snapshot.cycleEnd }
            .sorted { $0.occurredOn > $1.occurredOn }
    }

    private var emptyTitle: String {
        switch billFilter {
        case 1: return "Nothing is overdue."
        case 2: return "Nothing is due in the next 45 days."
        default: return "Add rent, utility bills, petrol, or an EMI."
        }
    }

    @ViewBuilder
    private func spendRow(_ expense: DailyExpense) -> some View {
        Button {
            editingSpend = expense
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(expense.note.isEmpty ? expense.kind.rawValue.capitalized : expense.note)
                        .font(.body)
                        .foregroundStyle(DesignSystem.textPrimary)
                    Text("\(expense.kind == .need ? "Need" : "Extra") · \(expense.occurredOn.formatted(.dateTime.day().month()))")
                        .font(.subheadline)
                        .foregroundStyle(DesignSystem.textSecondary)
                }
                Spacer()
                Text(CurrencyFormatter.format(expense.amount))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DesignSystem.textPrimary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(expense.note.isEmpty ? expense.kind.rawValue : expense.note), \(CurrencyFormatter.format(expense.amount)), \(expense.occurredOn.formatted(.dateTime.day().month()))")
        .accessibilityHint("Edits this spend")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Task { await modulesVM.deleteSpend(expense) }
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private func openAdd(_ section: FixedExpenseSection) {
        addSection = section
        showAddBill = true
    }
    
    private func billsForSegment(_ segment: Int) -> [BillItem] {
        switch segment {
        case 1: return modulesVM.overdueBills
        case 2: return modulesVM.upcomingBills
        default: return modulesVM.bills
        }
    }

    private func groupedSections(for segment: Int) -> [(FixedExpenseSection, [BillItem])] {
        let bills = billsForSegment(segment)
        let sections = FixedExpenseSection.addChoices
        return sections.compactMap { section in
            let rows = bills.filter { FixedExpenseSection.matching($0.category) == section }
            return rows.isEmpty ? nil : (section, rows)
        }
    }
    
    @ViewBuilder
    private func billRow(_ bill: BillItem) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(bill.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DesignSystem.textPrimary)
                Text(billDetail(bill))
                    .font(.subheadline)
                    .foregroundStyle(bill.isOverdue ? DesignSystem.error : DesignSystem.textSecondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(CurrencyFormatter.format(bill.amount))
                    .font(.body.weight(.semibold))
                Button(bill.isPaid ? "Paid" : "Mark paid") {
                    Task { await modulesVM.toggleBillPaid(bill) }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderless)
                .frame(minHeight: 44)
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(billAccessibilityLabel(bill))
        .accessibilityAction(named: bill.isPaid ? "Mark unpaid" : "Mark paid") {
            Task { await modulesVM.toggleBillPaid(bill) }
        }
        .accessibilityAction(named: "Remove") {
            Task { await modulesVM.deleteBill(bill) }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Task { await modulesVM.deleteBill(bill) }
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private func billDetail(_ bill: BillItem) -> String {
        var parts = ["Due \(bill.dueDate.shortDateString)"]
        if bill.isOverdue { parts.append("Overdue") }
        if FixedExpenseSection.matching(bill.category) == .emi, !bill.notes.isEmpty, bill.notes != bill.title {
            parts.append(bill.notes)
        }
        if bill.isRecurring { parts.append(bill.recurringFrequency) }
        if let plan = modulesVM.moneyPlan,
           let timing = MoneyDecisionEngine.creditCardBudgetTiming(
            for: bill,
            paydayDay: plan.paydayDay,
            now: Date(),
            calendar: .current
           ) {
            switch timing {
            case .setAsideThisMonth:
                parts.append("Counted this month, paid next month")
            case .paidFromLastMonth:
                parts.append("Paying last month's spending")
            }
        }
        if bill.isPaid { parts.append("Paid") }
        return parts.joined(separator: " · ")
    }

    private func billAccessibilityLabel(_ bill: BillItem) -> String {
        "\(bill.title), \(CurrencyFormatter.format(bill.amount)), \(billDetail(bill))"
    }
}

struct AddBillSheet: View {
    @ObservedObject var modulesVM: LifeModulesViewModel
    let currencySymbol: String
    var section: FixedExpenseSection = .rent
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var title = ""
    @State private var amount = ""
    @State private var category: FixedExpenseSection = .rent
    @State private var emiKind = "Home loan"
    @State private var emiCustom = ""
    @State private var dueDate = Date().adding(days: 7)
    @State private var isRecurring = true
    @State private var recurringFrequency = "Monthly"
    @State private var isSaving = false
    @State private var spoken = ""
    @State private var isFilling = false
    
    private let frequencies = ["Weekly", "Monthly", "Quarterly", "Yearly"]

    private var resolvedEMIKind: String {
        let custom = emiCustom.trimmingCharacters(in: .whitespacesAndNewlines)
        return emiKind == "Other" ? custom : emiKind
    }

    private var canSave: Bool {
        let named = !title.trimmingCharacters(in: .whitespaces).isEmpty
        guard !amount.isEmpty, !isSaving else { return false }
        if category == .emi {
            return named || !resolvedEMIKind.isEmpty
        }
        return named
    }
    
    var body: some View {
        NavigationStack {
            PremiumForm {
                Section("Bill Details") {
                    Picker("Section", selection: $category) {
                        ForEach(FixedExpenseSection.addChoices, id: \.self) { section in
                            Text(section.rawValue).tag(section)
                        }
                    }
                    if category == .emi {
                        Picker("What is this EMI?", selection: $emiKind) {
                            ForEach(FixedExpenseSection.emiKinds, id: \.self) { kind in
                                Text(kind).tag(kind)
                            }
                        }
                        if emiKind == "Other" {
                            TextField("Name this EMI", text: $emiCustom)
                        }
                    }
                    TextField(category == .emi ? "Label, optional" : "Title (e.g. Electricity)", text: $title)
                    TextField("Amount (\(currencySymbol))", text: $amount)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    DatePicker("Due Date", selection: $dueDate, displayedComponents: .date)
                    if category == .creditCard {
                        Text("Set the due date to the day you pay the card. If that day is next month, this month’s pay sets the money aside, and next month does not count it again. Don’t also log each swipe.")
                            .font(.footnote)
                            .foregroundStyle(DesignSystem.textSecondary)
                    }
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
                MoneySpokenFields(spoken: $spoken, working: isFilling, prompt: "Electricity 2400 on the 12th") {
                    Task { await applySpokenBill() }
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
                    .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .keyboardDismissToolbar(label: "Done")
            .onAppear { category = section }
            .onChange(of: section) { _, newValue in category = newValue }
        }
    }
    
    private func applySpokenBill() async {
        let text = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isFilling = true
        defer { isFilling = false }
        guard let fill = await MoneyPhraseService.fillFields(from: text) else { return }
        if let section = fill.section { category = section }
        if let amount = fill.amount { self.amount = String(format: "%.0f", amount) }
        if let note = fill.note, !note.isEmpty { title = note }
        if let day = fill.dueDay { dueDate = date(day: day) }
        if category == .emi, let emi = fill.emiKind { emiKind = emi }
    }

    private func date(day: Int) -> Date {
        let calendar = Calendar.current
        let base = category == .creditCard
            ? (calendar.date(byAdding: .month, value: 1, to: Date()) ?? Date())
            : dueDate
        var parts = calendar.dateComponents([.year, .month], from: base)
        parts.day = min(28, max(1, day))
        return calendar.date(from: parts) ?? dueDate
    }

    private func saveBill() {
        guard let amt = Double(amount) else { return }
        let typedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let emiName = resolvedEMIKind
        let savedTitle = typedTitle.isEmpty ? (category == .emi ? emiName : "") : typedTitle
        guard !savedTitle.isEmpty else { return }
        isSaving = true
        HapticManager.impact(.medium)
        Task {
            await modulesVM.addBill(
                title: savedTitle,
                amount: amt,
                dueDate: dueDate,
                category: category.rawValue,
                isRecurring: isRecurring,
                recurringFrequency: isRecurring ? recurringFrequency : "None",
                notes: category == .emi ? emiName : ""
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
                    Button("+ 250ml Water") { Task { await modulesVM.logWater(amountMl: 250) } }
                        .buttonStyle(PremiumPrimaryButtonStyle())

                    Button("+ 500ml Water") { Task { await modulesVM.logWater(amountMl: 500) } }
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
                                        Task { await modulesVM.removeWaterLog(log) }
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
                                        Task { await modulesVM.removeWaterLog(log) }
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
                ContactPickerViewController { name, phone, birthday in
                    let contact = RelationshipContact(name: name, phoneNumber: phone, relationship: "Friend", birthday: birthday, userId: "user")
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

                    if let birthday = contact.birthday {
                        Text("🎂 \(birthday.formatted(.dateTime.month(.wide).day()))")
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
    var onSelect: (String, String, Date?) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [
            CNContactPhoneNumbersKey,
            CNContactBirthdayKey
        ]
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    class Coordinator: NSObject, CNContactPickerDelegate {
        var onSelect: (String, String, Date?) -> Void

        init(onSelect: @escaping (String, String, Date?) -> Void) {
            self.onSelect = onSelect
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let fullName = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
            let phone = contact.phoneNumbers.first?.value.stringValue ?? ""
            let birthday = contact.birthday?.date
            onSelect(fullName.isEmpty ? "New Contact" : fullName, phone, birthday)
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
                                    HStack {
                                        Text(entry.createdAt.shortDateString)
                                            .font(.dsMetadata(weight: .semibold))
                                            .foregroundColor(DesignSystem.accentPrimary)
                                        Spacer()
                                        Button(action: {
                                            HapticManager.notification(.warning)
                                            Task { await modulesVM.deleteJournalEntry(entry) }
                                        }) {
                                            Image(systemName: "trash")
                                                .foregroundColor(DesignSystem.error)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Remove reflection")
                                    }
                                    Text(entry.content)
                                        .font(.dsSecondary())
                                        .foregroundColor(DesignSystem.textPrimary)
                                        .lineLimit(4)
                                }
                                .padding(DesignSystem.spacingMD)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                                        .fill(DesignSystem.contentSurfaceElevated)
                                )
                                .padding(.horizontal, DesignSystem.screenHorizontal)
                                .contextMenu {
                                    Button(role: .destructive, action: {
                                        Task { await modulesVM.deleteJournalEntry(entry) }
                                    }, label: {
                                        Label("Remove", systemImage: "trash")
                                    })
                                }
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
                    .fill(DesignSystem.contentSurface)
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
                systemPrompt: LookAfterPrompts.journalCalibrationSystem,
                tier: .economy
            ) {
                await MainActor.run {
                    let trimmed = JournalCalibrationSanitizer.plainText(from: calibration)
                    guard !trimmed.isEmpty else {
                        isProcessingAI = false
                        return
                    }
                    calibrationBadge = trimmed
                    UserCalibrationStore.append(
                        summary: trimmed,
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

struct MoneyPlannerHeader: View {
    @ObservedObject var modulesVM: LifeModulesViewModel
    var userId: String
    var sleepHours: Double?
    var onSetup: () -> Void
    var onStatements: (_ openingHistory: Bool) -> Void
    var onCard: () -> Void
    @Binding var billFilter: Int

    @AppStorage("moneyDecisionDismissedCycle") private var dismissedCycle = ""
    @State private var salaryText = ""
    @State private var payday = 1
    @State private var savingsText = "10"
    @State private var goalName = "Savings"
    @State private var showPayEditor = false
    @State private var showSplit = false
    @State private var split: MoneySplit?
    @State private var splitSentence = ""
    @State private var guideSentence = ""
    @State private var projectionSentence = ""
    @State private var limitText = ""
    @State private var paySentence = ""
    @State private var spokenPay = ""
    @State private var fillingPay = false
    @State private var isAnalysing = false

    private var snapshot: MoneyCycleSnapshot? {
        modulesVM.moneySnapshot(sleepHours: sleepHours)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let snapshot {
                VStack(alignment: .leading, spacing: 4) {
                    Text(cycleTitle(snapshot))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignSystem.textPrimary)
                    Text("Day \(guide?.dayNumber ?? 1) of \(guide?.dayCount ?? 1), \(guide?.daysLeft ?? 0) days left")
                        .font(.body)
                        .foregroundStyle(DesignSystem.textSecondary)
                    Text("Safe to spend")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DesignSystem.textSecondary)
                        .padding(.top, 8)
                    Text(CurrencyFormatter.format(snapshot.safeToSpend))
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(DesignSystem.textPrimary)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("Extras this week \(CurrencyFormatter.format(snapshot.extraLeftThisWeek))")
                        .font(.body)
                        .foregroundStyle(DesignSystem.textSecondary)
                    Text("Keeping \(CurrencyFormatter.format(snapshot.savingsKept)) for \(modulesVM.moneyPlan?.goalName ?? "Savings")")
                        .font(.body)
                        .foregroundStyle(DesignSystem.textSecondary)
                    if let kept = snapshot.previousCycleKept {
                        Text("Last cycle kept \(CurrencyFormatter.format(kept)).")
                            .font(.body)
                            .foregroundStyle(DesignSystem.textSecondary)
                    }
                }
                .accessibilityElement(children: .combine)

                if let projection {
                    MoneyProjectionCard(
                        projection: projection,
                        suggestion: projectionSentence.isEmpty ? projection.sentence : projectionSentence,
                        onUseSuggested: { Task { await applySuggestedLimit(projection) } }
                    )
                }

                if let split = homeSplit, split.salary > 0 {
                    MoneySplitBar(lines: split.lines)
                        .padding(.top, 4)
                }

                if let guide {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Save \(Int(guide.recommendedSavingsPercent.rounded()))% · \(CurrencyFormatter.format(guide.recommendedMonthlySave)) a month")
                            .font(.body.weight(.semibold))
                        Text("Emergency fund \(CurrencyFormatter.format(guide.emergencyTarget)) · about \(guide.monthsToFund) months at that pace")
                            .font(.body)
                            .foregroundStyle(DesignSystem.textSecondary)
                        TextField("Suggestion", text: $guideSentence, axis: .vertical)
                            .lineLimit(2...5)
                            .font(.body)
                            .foregroundStyle(DesignSystem.textPrimary)
                        Button("Apply suggestion") {
                            Task { await applyRecommendedSavings(guide) }
                        }
                        .buttonStyle(.bordered)
                        .font(.body.weight(.semibold))
                        .frame(minHeight: 44)
                        .disabled(savingsAlreadyMatches(guide))
                        .accessibilityHint("Writes the recommended savings percent into pay")
                    }
                }

                Button("Edit pay") { openPayEditor() }
                    .font(.body.weight(.semibold))
                    .frame(minHeight: 44)
                Button {
                    analysePay()
                } label: {
                    HStack {
                        if isAnalysing {
                            ProgressView()
                        }
                        Text("Analyse pay")
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(isAnalysing)
                .accessibilityLabel("Analyse how to split this month's pay")
                .accessibilityHint("Save, home, bills, essentials, shopping and luxury, and a cushion")

                Button("Import 6 months") { onStatements(true) }
                    .font(.body.weight(.semibold))
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityHint("Reads a bank statement and adds spends that are not already logged")
                Button("Upload last month") { onStatements(false) }
                    .font(.body.weight(.semibold))
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityHint("Checks last month's statement against logged spends")
                Button("Card statement") { onCard() }
                    .font(.body.weight(.semibold))
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityHint("Sorts a credit card statement and recommends what to pay")

                let cycleKey = String(snapshot.cycleStart.timeIntervalSince1970)
                if snapshot.suggestion != nil, dismissedCycle != cycleKey, !modulesVM.decisionSentence.isEmpty {
                    Text(modulesVM.decisionSentence)
                        .font(.body)
                        .foregroundStyle(DesignSystem.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 8) {
                        Button("Review fixed costs") { billFilter = 0 }
                        Button("Dismiss for this cycle") { dismissedCycle = cycleKey }
                    }
                    .buttonStyle(.bordered)
                    .font(.body.weight(.semibold))
                }
            } else {
                Text("Set up this month’s pay")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(DesignSystem.textPrimary)
                Text("Salary, payday, and the fixed costs that leave before spending.")
                    .font(.body)
                    .foregroundStyle(DesignSystem.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Set up finance") { onSetup() }
                    .font(.body.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                Button("Import 6 months") { onStatements(true) }
                    .font(.body.weight(.semibold))
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, minHeight: 44)
                Button("Card statement") { onCard() }
                    .font(.body.weight(.semibold))
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .elevatedSurface()
        .sheet(isPresented: $showPayEditor) {
            payEditor
        }
        .sheet(isPresented: $showSplit) {
            splitSheet
        }
        .task {
            await modulesVM.refreshDecisionSentenceWithVoice(sleepHours: sleepHours)
            if let guide {
                guideSentence = guide.sentence
                guideSentence = await MoneyPhraseService.phraseGuide(guide)
            }
            if let projection {
                projectionSentence = projection.sentence
                projectionSentence = await MoneyPhraseService.phraseProjection(projection)
            }
        }
    }

    private var guide: MoneyPlanGuide? {
        guard let plan = modulesVM.moneyPlan else { return nil }
        return MoneyDecisionEngine.guide(plan: plan, bills: modulesVM.bills, now: Date(), calendar: .current)
    }

    private var projection: MoneyMonthProjection? {
        guard let plan = modulesVM.moneyPlan else { return nil }
        return MoneyDecisionEngine.projection(
            plan: plan,
            bills: modulesVM.bills,
            expenses: modulesVM.dailyExpenses,
            now: Date(),
            calendar: .current
        )
    }

    private var homeSplit: MoneySplit? {
        guard let plan = modulesVM.moneyPlan else { return nil }
        return MoneyDecisionEngine.split(plan: plan, bills: modulesVM.bills, now: Date(), calendar: .current)
    }

    private func cycleTitle(_ snapshot: MoneyCycleSnapshot) -> String {
        let start = snapshot.cycleStart.formatted(.dateTime.day().month())
        let end = snapshot.cycleEnd.formatted(.dateTime.day().month())
        return "\(start) – \(end)"
    }

    private var payRecommendation: MoneyPlanGuide? {
        let salary = Double(salaryText) ?? 0
        guard salary > 0 else { return nil }
        var plan = modulesVM.moneyPlan ?? MoneyPlan(monthlySalary: salary, paydayDay: payday, userId: userId)
        plan.monthlySalary = salary
        plan.paydayDay = payday
        plan.goalName = goalName.isEmpty ? "Savings" : goalName
        return MoneyDecisionEngine.guide(plan: plan, bills: modulesVM.bills, now: Date(), calendar: .current)
    }

    private var payEditor: some View {
        NavigationStack {
            Form {
                Section("Pay") {
                    TextField("Monthly pay", text: $salaryText)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel("Monthly pay")
                    Stepper(value: $payday, in: 1...28) {
                        Text("Payday, day \(payday)")
                    }
                    .accessibilityValue("Day \(payday)")
                    TextField("Savings percent", text: $savingsText)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel("Savings percent")
                    TextField("Spending limit", text: $limitText)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel("Spending limit")
                        .accessibilityHint("Leave blank to use the suggested monthly limit")
                    if let offer = payRecommendation {
                        TextField("Suggestion", text: $paySentence, axis: .vertical)
                            .lineLimit(2...5)
                            .font(.subheadline)
                        Button("Apply suggestion") {
                            savingsText = String(Int(offer.recommendedSavingsPercent.rounded()))
                        }
                        .font(.body.weight(.semibold))
                        .disabled(Int(offer.recommendedSavingsPercent.rounded()) == Int(Double(savingsText) ?? -1))
                    }
                    TextField("Goal name", text: $goalName)
                        .accessibilityLabel("Goal name")
                    MoneySpokenFields(spoken: $spokenPay, working: fillingPay) {
                        Task { await applySpokenPay() }
                    }
                }
            }
            .navigationTitle("Pay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showPayEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await modulesVM.saveSalary(
                                amount: Double(salaryText) ?? 0,
                                payday: payday,
                                goalName: goalName,
                                userId: userId,
                                savingsPercent: Double(savingsText),
                                spendingLimit: Double(limitText),
                                clearSpendingLimit: limitText.trimmingCharacters(in: .whitespaces).isEmpty
                            )
                            await modulesVM.refreshDecisionSentenceWithVoice(sleepHours: sleepHours)
                            showPayEditor = false
                        }
                    }
                    .disabled((Double(salaryText) ?? 0) <= 0)
                }
            }
            .keyboardDismissToolbar(label: "Done")
            .task(id: salaryText) {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled, let offer = payRecommendation else { return }
                paySentence = offer.savingsReason
                paySentence = await MoneyPhraseService.phraseGuide(offer)
            }
        }
        .presentationDetents([.large])
    }

    private func applyRecommendedSavings(_ guide: MoneyPlanGuide) async {
        guard let plan = modulesVM.moneyPlan else { return }
        await modulesVM.saveSalary(
            amount: plan.monthlySalary,
            payday: plan.paydayDay,
            goalName: plan.goalName,
            userId: userId,
            savingsPercent: guide.recommendedSavingsPercent
        )
        await modulesVM.refreshDecisionSentenceWithVoice(sleepHours: sleepHours)
    }

    private func applySuggestedLimit(_ projection: MoneyMonthProjection) async {
        guard let plan = modulesVM.moneyPlan else { return }
        await modulesVM.saveSalary(
            amount: plan.monthlySalary,
            payday: plan.paydayDay,
            goalName: plan.goalName,
            userId: userId,
            spendingLimit: projection.suggestedLimit
        )
        await modulesVM.refreshDecisionSentenceWithVoice(sleepHours: sleepHours)
        projectionSentence = projection.sentence
        projectionSentence = await MoneyPhraseService.phraseProjection(
            MoneyDecisionEngine.projection(
                plan: modulesVM.moneyPlan ?? plan,
                bills: modulesVM.bills,
                expenses: modulesVM.dailyExpenses,
                now: Date(),
                calendar: .current
            ) ?? projection
        )
    }

    private func savingsAlreadyMatches(_ guide: MoneyPlanGuide) -> Bool {
        guard let plan = modulesVM.moneyPlan else { return false }
        return abs(plan.savingsPercent - guide.recommendedSavingsPercent) < 0.5
    }

    private func applySpokenPay() async {
        let text = spokenPay.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        fillingPay = true
        defer { fillingPay = false }
        guard let fill = await MoneyPhraseService.fillFields(from: text) else { return }
        if let amount = fill.amount { salaryText = String(format: "%.0f", amount) }
        if let day = fill.payday { payday = min(28, max(1, day)) }
        if let percent = fill.savingsPercent { savingsText = String(Int(percent.rounded())) }
        if let goal = fill.goalName, !goal.isEmpty { goalName = goal }
    }

    private func openPayEditor() {
        if let plan = modulesVM.moneyPlan {
            salaryText = String(format: "%.0f", plan.monthlySalary)
            payday = min(28, max(1, plan.paydayDay))
            savingsText = String(format: "%.0f", plan.savingsPercent)
            goalName = plan.goalName
            if let limit = plan.spendingLimit, limit > 0 {
                limitText = String(format: "%.0f", limit)
            } else {
                limitText = ""
            }
        }
        showPayEditor = true
    }

    private func analysePay() {
        guard let plan = modulesVM.moneyPlan else { return }
        let result = MoneyDecisionEngine.split(
            plan: plan,
            bills: modulesVM.bills,
            now: Date(),
            calendar: .current
        )
        guard let result else { return }
        split = result
        splitSentence = result.sentence
        showSplit = true
        isAnalysing = true
        Task {
            splitSentence = await MoneyPhraseService.phraseSplit(result)
            isAnalysing = false
        }
    }

    private var splitSheet: some View {
        NavigationStack {
            List {
                if let lines = split?.lines, (split?.salary ?? 0) > 0 {
                    Section {
                        MoneySplitBar(lines: lines)
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    }
                }
                if !splitSentence.isEmpty {
                    Section {
                        TextField("Suggestion", text: $splitSentence, axis: .vertical)
                            .lineLimit(2...5)
                            .font(.body)
                        if let guide {
                            Button("Apply suggestion") {
                                Task { await applyRecommendedSavings(guide) }
                            }
                            .disabled(savingsAlreadyMatches(guide))
                        }
                    }
                }
                Section("This month") {
                    ForEach(split?.lines ?? []) { line in
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.title)
                                    .font(.body.weight(.semibold))
                                Text(line.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(DesignSystem.textSecondary)
                            }
                            Spacer(minLength: 8)
                            Text(CurrencyFormatter.format(line.amount))
                                .font(.body.weight(.semibold))
                        }
                        .frame(minHeight: 44)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .navigationTitle("Analyse pay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showSplit = false }
                }
            }
        }
        .presentationDetents([.large])
    }
}

struct LogSpendSheet: View {
    @ObservedObject var modulesVM: LifeModulesViewModel
    var userId: String
    var sleepHours: Double?

    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var note = ""
    @State private var kind: SpendKind = .need
    @State private var captureText = ""
    @State private var suggestedKind: SpendKind?
    @State private var suggestedNote = ""
    @State private var isFilling = false
    @State private var kindTask: Task<Void, Never>?

    private var amount: Double { Double(amountText) ?? 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section("Amount") {
                    TextField("0", text: $amountText)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold))
                        .accessibilityLabel("Amount")
                }
                Section {
                    Picker("Kind", selection: $kind) {
                        Text("Need").tag(SpendKind.need)
                        Text("Extra").tag(SpendKind.extra)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Need or Extra")
                    Text("Need covers food, travel, and household. Extra is the rest.")
                        .font(.footnote)
                        .foregroundStyle(DesignSystem.textSecondary)
                }
                Section("Note") {
                    TextField("What was it?", text: $note)
                    if let suggestedKind, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(suggestedNote.isEmpty ? "Suggestion: \(suggestedKind == .extra ? "Extra" : "Need")" : "Suggestion: \(suggestedKind == .extra ? "Extra" : "Need"). \(suggestedNote)")
                            .font(.subheadline)
                            .foregroundStyle(DesignSystem.textSecondary)
                        Button("Apply suggestion") {
                            kind = suggestedKind
                            if !suggestedNote.isEmpty { note = suggestedNote }
                        }
                    }
                }
                MoneySpokenFields(spoken: $captureText, working: isFilling) {
                    Task { await applySpokenSpend() }
                }
            }
            .navigationTitle("Log a spend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveSpend() }
                        .disabled(amount <= 0)
                }
            }
            .keyboardDismissToolbar(label: "Done")
            .onChange(of: note) { _, newValue in
                refreshSpendSuggestion(newValue)
            }
            .confirmationDialog(
                "Save this extra of \(CurrencyFormatter.format(modulesVM.pendingLargeExtra?.amount ?? amount))?",
                isPresented: largeExtraPresented,
                titleVisibility: .visible
            ) {
                Button("Save") {
                    Task {
                        await modulesVM.confirmPendingExtra()
                        await modulesVM.refreshDecisionSentenceWithVoice(sleepHours: sleepHours)
                        dismiss()
                    }
                }
                Button("Leave it", role: .cancel) { modulesVM.dismissPendingExtra() }
            }
        }
        .presentationDetents([.large])
    }

    private var largeExtraPresented: Binding<Bool> {
        Binding(
            get: { modulesVM.pendingLargeExtra != nil },
            set: { if !$0 { modulesVM.dismissPendingExtra() } }
        )
    }

    private func applySpokenSpend() async {
        let text = captureText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isFilling = true
        defer { isFilling = false }
        guard let fill = await MoneyPhraseService.fillFields(from: text) else { return }
        if let amount = fill.amount { amountText = String(format: "%.0f", amount) }
        if let written = fill.note, !written.isEmpty { note = written }
        if let kind = fill.kind { self.kind = kind }
    }

    private func refreshSpendSuggestion(_ newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            suggestedKind = nil
            suggestedNote = ""
            return
        }
        suggestedKind = modulesVM.chipKind(for: trimmed)
        suggestedNote = trimmed
        kindTask?.cancel()
        kindTask = Task {
            let cleaned = await MoneyPhraseService.cleanNote(trimmed)
            let suggested = await MoneyPhraseService.suggestKind(note: trimmed)
            guard !Task.isCancelled else { return }
            suggestedKind = suggested
            suggestedNote = cleaned
        }
    }

    private func saveSpend() {
        Task {
            let saved = await modulesVM.logSpend(amount: amount, kind: kind, note: note, userId: userId)
            if saved {
                await modulesVM.refreshDecisionSentenceWithVoice(sleepHours: sleepHours)
                dismiss()
            }
        }
    }
}

struct MoneyProjectionCard: View {
    let projection: MoneyMonthProjection
    var suggestion: String
    var onUseSuggested: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(projection.usesOwnLimit ? "Spending limit" : "Suggested limit")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(paceTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(paceColor)
            }
            Text("\(CurrencyFormatter.format(projection.spent)) of \(CurrencyFormatter.format(projection.limit))")
                .font(.title3.weight(.bold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            MoneyLimitBar(spent: projection.spent, limit: projection.limit, pace: projection.pace)
            Text("At this pace, \(CurrencyFormatter.format(projection.projectedSpend)) by payday")
                .font(.body)
                .foregroundStyle(DesignSystem.textSecondary)
            Text("\(CurrencyFormatter.format(projection.dailyAllowance)) a day for the next \(projection.daysLeft) days")
                .font(.body)
            Text(suggestion)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            if projection.usesOwnLimit, abs(projection.limit - projection.suggestedLimit) >= 1 {
                Button("Use suggested limit \(CurrencyFormatter.format(projection.suggestedLimit))", action: onUseSuggested)
                    .font(.body.weight(.semibold))
                    .frame(minHeight: 44)
            }
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(paceTitle). Spent \(CurrencyFormatter.format(projection.spent)) of \(CurrencyFormatter.format(projection.limit)). At this pace \(CurrencyFormatter.format(projection.projectedSpend)). \(CurrencyFormatter.format(projection.dailyAllowance)) a day.")
    }

    private var paceTitle: String {
        switch projection.pace {
        case .onTrack: return "On track"
        case .room: return "Room left"
        case .over: return "Over pace"
        }
    }

    private var paceColor: Color {
        switch projection.pace {
        case .onTrack: return DesignSystem.accentPrimary
        case .room: return DesignSystem.accentPrimary
        case .over: return DesignSystem.error
        }
    }
}

struct MoneyLimitBar: View {
    var spent: Double
    var limit: Double
    var pace: MoneyProjectionPace

    var body: some View {
        GeometryReader { geo in
            let fraction = limit > 0 ? min(1, spent / limit) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(DesignSystem.contentSurface)
                Capsule()
                    .fill(pace == .over ? DesignSystem.error : DesignSystem.accentPrimary)
                    .frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

struct MoneySplitBar: View {
    let lines: [MoneySplitLine]

    var body: some View {
        let shown = lines.filter { $0.amount > 0 }
        let total = shown.reduce(0) { $0 + $1.amount }
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(shown) { line in
                        Rectangle()
                            .fill(Self.color(line.title))
                            .frame(width: total > 0 ? geo.size.width * line.amount / total : 0)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 14)
            .accessibilityLabel(shown.map { "\($0.title) \(CurrencyFormatter.format($0.amount))" }.joined(separator: ", "))

            ForEach(shown) { line in
                HStack(spacing: 8) {
                    Circle()
                        .fill(Self.color(line.title))
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(line.title)
                        .font(.subheadline)
                    Spacer(minLength: 8)
                    Text(CurrencyFormatter.format(line.amount))
                        .font(.subheadline.weight(.semibold))
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private static func color(_ title: String) -> Color {
        switch title {
        case "Save": return .blue
        case "Home and dues": return .indigo
        case "Everyday bills": return .teal
        case "Essentials": return .green
        case "Shopping and luxury": return .orange
        default: return .gray
        }
    }
}

struct EditSpendSheet: View {
    @ObservedObject var modulesVM: LifeModulesViewModel
    var expense: DailyExpense
    var sleepHours: Double?

    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var note = ""
    @State private var kind: SpendKind = .need
    @State private var occurredOn = Date()
    @State private var suggestedKind: SpendKind?
    @State private var suggestedNote = ""
    @State private var acceptNoteChanges = false
    @State private var kindTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section("Amount") {
                    TextField("0", text: $amountText)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold))
                        .accessibilityLabel("Amount")
                }
                Section {
                    Picker("Kind", selection: $kind) {
                        Text("Need").tag(SpendKind.need)
                        Text("Extra").tag(SpendKind.extra)
                    }
                    .pickerStyle(.segmented)
                }
                Section("Note") {
                    TextField("What was it?", text: $note)
                    if let suggestedKind, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(suggestedNote.isEmpty ? "Suggestion: \(suggestedKind == .extra ? "Extra" : "Need")" : "Suggestion: \(suggestedKind == .extra ? "Extra" : "Need"). \(suggestedNote)")
                            .font(.subheadline)
                            .foregroundStyle(DesignSystem.textSecondary)
                        Button("Apply suggestion") {
                            kind = suggestedKind
                            if !suggestedNote.isEmpty { note = suggestedNote }
                        }
                    }
                }
                Section("Day") {
                    DatePicker("Date", selection: $occurredOn, displayedComponents: .date)
                }
            }
            .navigationTitle("Edit spend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled((Double(amountText) ?? 0) <= 0)
                }
            }
            .keyboardDismissToolbar(label: "Done")
            .onAppear {
                amountText = String(format: "%.0f", expense.amount)
                note = expense.note
                kind = expense.kind
                occurredOn = expense.occurredOn
                Task { @MainActor in acceptNoteChanges = true }
            }
            .onChange(of: note) { _, newValue in
                guard acceptNoteChanges else { return }
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.count >= 2 else {
                    suggestedKind = nil
                    suggestedNote = ""
                    return
                }
                suggestedKind = modulesVM.chipKind(for: trimmed)
                suggestedNote = trimmed
                kindTask?.cancel()
                kindTask = Task {
                    let cleaned = await MoneyPhraseService.cleanNote(trimmed)
                    let suggested = await MoneyPhraseService.suggestKind(note: trimmed)
                    guard !Task.isCancelled else { return }
                    suggestedKind = suggested
                    suggestedNote = cleaned
                }
            }
        }
        .presentationDetents([.large])
    }

    private func save() {
        var updated = expense
        updated.amount = Double(amountText) ?? 0
        updated.kind = kind
        updated.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.occurredOn = occurredOn
        Task {
            await modulesVM.updateSpend(updated)
            await modulesVM.refreshDecisionSentenceWithVoice(sleepHours: sleepHours)
            dismiss()
        }
    }
}

private struct FixedCostDraft {
    var section: FixedExpenseSection
    var amountText = ""
    var dueDay = 1
    var emiKind = FixedExpenseSection.emiKinds[0]

    var amount: Double { Double(amountText) ?? 0 }
}

struct FinanceOnboardingSheet: View {
    @ObservedObject var modulesVM: LifeModulesViewModel
    var userId: String
    var sleepHours: Double?

    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var salaryText = ""
    @State private var payday = 1
    @State private var savingsText = ""
    @State private var goalName = "Savings"
    @State private var drafts = FixedExpenseSection.addChoices.map { FixedCostDraft(section: $0) }
    @State private var voice = ""
    @State private var spoken = ""
    @State private var isFilling = false
    @State private var isSaving = false
    @State private var showStatements = false

    private var totalSteps: Int { 2 + drafts.count + 1 }
    private var reviewStep: Int { 2 + drafts.count }
    private var salary: Double { Double(salaryText) ?? 0 }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("Step \(step + 1) of \(totalSteps)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignSystem.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .accessibilityLabel("Step \(step + 1) of \(totalSteps)")

                Group {
                    if step == 0 {
                        payStep
                    } else if step == 1 {
                        savingsStep
                    } else if step == reviewStep {
                        reviewStepView
                    } else if let index = sectionIndex {
                        fixedStep(index)
                    }
                }

                Button(primaryTitle) { advance() }
                    .font(.headline)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .disabled(primaryDisabled)
                    .padding(16)
            }
            .navigationTitle(stepTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(step == 0 ? "Cancel" : "Back") {
                        if step == 0 { dismiss() } else { step -= 1 }
                    }
                }
            }
            .keyboardDismissToolbar(label: "Done")
            .task(id: step) {
                guard step == 1 || step == reviewStep, let guide = previewGuide else { return }
                voice = guide.sentence
                voice = await MoneyPhraseService.phraseGuide(guide)
            }
            .sheet(isPresented: $showStatements) {
                StatementImportSheet(modulesVM: modulesVM, userId: userId, openingHistory: true)
            }
        }
        .presentationDetents([.large])
    }

    private var payStep: some View {
        Form {
            Section("Monthly pay") {
                TextField("Amount", text: $salaryText)
                    .keyboardType(.decimalPad)
                    .font(.title2.weight(.semibold))
                    .accessibilityLabel("Monthly pay")
                Stepper(value: $payday, in: 1...28) {
                    Text("Payday, day \(payday)")
                }
            }
            Section {
                Text("The cycle runs from this day until the same day next month.")
                    .font(.subheadline)
                    .foregroundStyle(DesignSystem.textSecondary)
            }
            MoneySpokenFields(spoken: $spoken, working: isFilling, prompt: "80,000 paid on the 1st") {
                Task { await applySpokenStep() }
            }
        }
    }

    private var savingsStep: some View {
        Form {
            Section("Saving for") {
                TextField("Goal name", text: $goalName)
                TextField("Savings percent", text: $savingsText)
                    .keyboardType(.decimalPad)
                if let guide = previewGuide {
                    TextField("Suggestion", text: $voice, axis: .vertical)
                        .lineLimit(2...5)
                    Button("Apply suggestion") {
                        savingsText = String(Int(guide.recommendedSavingsPercent.rounded()))
                    }
                    .disabled(Int(guide.recommendedSavingsPercent.rounded()) == Int(Double(savingsText) ?? -1))
                }
            }
            MoneySpokenFields(spoken: $spoken, working: isFilling, prompt: "Save 20 percent for a trip") {
                Task { await applySpokenStep() }
            }
        }
    }

    private func fixedStep(_ index: Int) -> some View {
        let section = drafts[index].section
        return Form {
            Section(section.rawValue) {
                TextField("Monthly amount", text: $drafts[index].amountText)
                    .keyboardType(.decimalPad)
                    .font(.title2.weight(.semibold))
                    .accessibilityLabel("\(section.rawValue) amount")
                Stepper(value: $drafts[index].dueDay, in: 1...28) {
                    Text("Due on day \(drafts[index].dueDay)")
                }
                if section == .emi {
                    Picker("What is this EMI?", selection: $drafts[index].emiKind) {
                        ForEach(FixedExpenseSection.emiKinds, id: \.self) { kind in
                            Text(kind).tag(kind)
                        }
                    }
                }
                if section == .creditCard {
                    Text("Use the day you pay the card. That amount is counted in the month before, and not again on the payment day. Don’t also log each swipe.")
                        .font(.subheadline)
                        .foregroundStyle(DesignSystem.textSecondary)
                }
            }
            Section {
                Text("Leave the amount empty to skip.")
                    .font(.subheadline)
                    .foregroundStyle(DesignSystem.textSecondary)
            }
            MoneySpokenFields(spoken: $spoken, working: isFilling, prompt: "18000 on the 5th") {
                Task { await applySpokenStep() }
            }
        }
    }

    private var reviewStepView: some View {
        Form {
            if let guide = previewGuide, let split = previewSplit {
                Section {
                    MoneySplitBar(lines: split.lines)
                }
                Section("Savings and emergency fund") {
                    Text("Save \(Int(guide.recommendedSavingsPercent.rounded()))% · \(CurrencyFormatter.format(guide.recommendedMonthlySave)) a month")
                    Text("Emergency fund \(CurrencyFormatter.format(guide.emergencyTarget)) · about \(guide.monthsToFund) months")
                        .foregroundStyle(DesignSystem.textSecondary)
                    TextField("Suggestion", text: $voice, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            Section {
                Button("Import 6 months of statements") { showStatements = true }
                    .frame(minHeight: 44)
            }
            Section("Fixed costs") {
                let kept = drafts.filter { $0.amount > 0 }
                if kept.isEmpty {
                    Text("None added. You can add them later.")
                        .foregroundStyle(DesignSystem.textSecondary)
                } else {
                    ForEach(kept, id: \.section) { draft in
                        HStack {
                            Text(draft.section == .emi ? draft.emiKind : draft.section.rawValue)
                            Spacer()
                            Text(CurrencyFormatter.format(draft.amount))
                        }
                    }
                }
            }
        }
    }

    private var sectionIndex: Int? {
        guard step >= 2, step < reviewStep else { return nil }
        return step - 2
    }

    private var stepTitle: String {
        if step == 0 { return "Pay" }
        if step == 1 { return "Savings" }
        if step == reviewStep { return "Your plan" }
        if let index = sectionIndex { return drafts[index].section.rawValue }
        return "Finance"
    }

    private var primaryTitle: String {
        if step == reviewStep { return isSaving ? "Saving" : "Save setup" }
        if let index = sectionIndex, drafts[index].amount <= 0 { return "Skip" }
        return "Next"
    }

    private var primaryDisabled: Bool {
        if isSaving { return true }
        if step == 0 { return salary <= 0 }
        return false
    }

    private func advance() {
        if step == 1, savingsText.trimmingCharacters(in: .whitespaces).isEmpty, let guide = previewGuide {
            savingsText = String(Int(guide.recommendedSavingsPercent.rounded()))
        }
        if step == reviewStep {
            saveSetup()
            return
        }
        spoken = ""
        step += 1
    }

    private func applySpokenStep() async {
        let text = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isFilling = true
        defer { isFilling = false }
        guard let fill = await MoneyPhraseService.fillFields(from: text) else { return }
        if step == 0 {
            if let amount = fill.amount { salaryText = String(format: "%.0f", amount) }
            if let day = fill.payday { payday = min(28, max(1, day)) }
        } else if step == 1 {
            if let percent = fill.savingsPercent { savingsText = String(Int(percent.rounded())) }
            if let goal = fill.goalName, !goal.isEmpty { goalName = goal }
        } else if let index = sectionIndex {
            if let amount = fill.amount { drafts[index].amountText = String(format: "%.0f", amount) }
            if let day = fill.dueDay { drafts[index].dueDay = min(28, max(1, day)) }
            if drafts[index].section == .emi, let emi = fill.emiKind {
                drafts[index].emiKind = emi
            }
        }
    }

    private func saveSetup() {
        guard salary > 0 else { return }
        isSaving = true
        let percent = Double(savingsText) ?? previewGuide?.recommendedSavingsPercent ?? 10
        Task {
            await modulesVM.saveSalary(
                amount: salary,
                payday: payday,
                goalName: goalName,
                userId: userId,
                savingsPercent: percent
            )
            for draft in drafts where draft.amount > 0 {
                let title = draft.section == .emi ? draft.emiKind : draft.section.rawValue
                await modulesVM.addBill(
                    title: title,
                    amount: draft.amount,
                    dueDate: dueDate(day: draft.dueDay, section: draft.section),
                    category: draft.section.rawValue,
                    notes: draft.section == .emi ? draft.emiKind : ""
                )
            }
            await modulesVM.refreshDecisionSentenceWithVoice(sleepHours: sleepHours)
            dismiss()
        }
    }

    private var previewGuide: MoneyPlanGuide? {
        guard salary > 0 else { return nil }
        let percent = Double(savingsText) ?? 10
        let plan = MoneyPlan(
            monthlySalary: salary,
            paydayDay: payday,
            savingsPercent: percent,
            goalName: goalName.isEmpty ? "Savings" : goalName,
            userId: userId
        )
        return MoneyDecisionEngine.guide(plan: plan, bills: previewBills, now: Date(), calendar: .current)
    }

    private var previewSplit: MoneySplit? {
        guard salary > 0 else { return nil }
        let percent = Double(savingsText) ?? previewGuide?.recommendedSavingsPercent ?? 10
        let plan = MoneyPlan(
            monthlySalary: salary,
            paydayDay: payday,
            savingsPercent: percent,
            goalName: goalName.isEmpty ? "Savings" : goalName,
            userId: userId
        )
        return MoneyDecisionEngine.split(plan: plan, bills: previewBills, now: Date(), calendar: .current)
    }

    private var previewBills: [BillItem] {
        let added = drafts.compactMap { draft -> BillItem? in
            guard draft.amount > 0 else { return nil }
            return BillItem(
                title: draft.section == .emi ? draft.emiKind : draft.section.rawValue,
                amount: draft.amount,
                dueDate: dueDate(day: draft.dueDay, section: draft.section),
                category: draft.section.rawValue,
                notes: draft.section == .emi ? draft.emiKind : "",
                userId: userId
            )
        }
        return modulesVM.bills + added
    }

    private func dueDate(day: Int, section: FixedExpenseSection) -> Date {
        let calendar = Calendar.current
        let base = section == .creditCard
            ? (calendar.date(byAdding: .month, value: 1, to: Date()) ?? Date())
            : Date()
        var parts = calendar.dateComponents([.year, .month], from: base)
        parts.day = min(28, max(1, day))
        return calendar.date(from: parts) ?? base
    }
}

private struct MoneySpokenFields: View {
    @Binding var spoken: String
    var working: Bool
    var prompt: String = "240 on dinner"
    var onApply: () -> Void

    var body: some View {
        Section("Or say it") {
            TextField(prompt, text: $spoken, axis: .vertical)
                .lineLimit(2...4)
            Button(working ? "Filling…" : "Apply suggestion") {
                onApply()
            }
            .disabled(working || spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

struct StatementImportSheet: View {
    @ObservedObject var modulesVM: LifeModulesViewModel
    var userId: String
    var openingHistory: Bool
    var cardStatement: Bool = false

    @Environment(\.dismiss) private var dismiss
    @State private var showPicker = false
    @State private var working = false
    @State private var errorText = ""
    @State private var voice = ""
    @State private var analysis: StatementAnalysis?
    @State private var cards: [CardStatementReport] = []
    @State private var tally: StatementTally?
    @State private var pending: [StatementLine] = []
    @State private var selectedCharges: Set<String> = []
    @State private var anomalies: [StatementAnomaly] = []
    @State private var resultText = ""
    @State private var queued: [QueuedStatement] = []
    @State private var password = ""
    @State private var askPassword = false
    @State private var passwordNote = ""

    private struct QueuedStatement {
        var name: String
        var data: Data
    }

    private var fileTypes: [UTType] {
        var types: [UTType] = [.pdf, .plainText, .text, .commaSeparatedText, .spreadsheet]
        for ext in ["csv", "tsv", "txt", "xls", "xlsx"] {
            if let type = UTType(filenameExtension: ext) { types.append(type) }
        }
        return types
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(cardStatement
                         ? "Upload one statement per card as PDF, Excel, or text. Each card stays separate, sorted into needs and extras. A locked file asks for its password."
                         : openingHistory
                         ? "Upload the last 6 months as PDF, Excel, or text. If the bank locked the file, you’ll be asked for the password."
                         : "Upload last month’s statement as PDF, Excel, or text. Logged spends are checked against it, and missing lines can be added. A locked file asks for its password.")
                        .font(.body)
                        .foregroundStyle(DesignSystem.textSecondary)
                    Button(working ? "Reading" : "Choose statement") { showPicker = true }
                        .disabled(working)
                        .frame(minHeight: 44)
                }
                if askPassword {
                    Section("Password") {
                        Text(passwordNote)
                            .foregroundStyle(DesignSystem.textSecondary)
                        SecureField("Statement password", text: $password)
                        Button("Unlock") { Task { await openQueued(password: password) } }
                            .disabled(working || password.isEmpty)
                            .frame(minHeight: 44)
                    }
                }
                if !errorText.isEmpty {
                    Section {
                        Text(errorText)
                            .foregroundStyle(DesignSystem.error)
                    }
                }
                if let analysis {
                    Section(openingHistory ? "Six month spend" : "Statement") {
                        TextField("Suggestion", text: $voice, axis: .vertical)
                            .lineLimit(2...6)
                        ForEach(visibleMonths(analysis)) { month in
                            HStack {
                                Text(monthLabel(month))
                                Spacer()
                                Text(CurrencyFormatter.format(month.moneyOut))
                            }
                        }
                        Text("Average \(CurrencyFormatter.format(analysis.averageOut)) a month")
                            .font(.body.weight(.semibold))
                    }
                    if openingHistory, !analysis.repeating.isEmpty {
                        Section("Repeating bills") {
                            ForEach(analysis.repeating) { charge in
                                Toggle(isOn: binding(for: charge.id)) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(charge.section.rawValue)
                                        Text("\(CurrencyFormatter.format(charge.amount)) · day \(charge.dueDay) · \(charge.months) months")
                                            .font(.subheadline)
                                            .foregroundStyle(DesignSystem.textSecondary)
                                    }
                                }
                                .frame(minHeight: 44)
                            }
                        }
                    }
                    if !anomalies.isEmpty {
                        Section("Check these") {
                            ForEach(anomalies) { item in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(item.question)
                                        .font(.body)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if item.kind == .unloggedSubscription {
                                        Button("I still subscribe") { confirmSubscription(item) }
                                            .frame(minHeight: 44)
                                        Button("Not subscribed") {
                                            anomalies.removeAll { $0.id == item.id }
                                        }
                                        .frame(minHeight: 44)
                                    } else {
                                        Button("I'll check") {
                                            anomalies.removeAll { $0.id == item.id }
                                        }
                                        .frame(minHeight: 44)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                if let tally {
                    Section(openingHistory ? "Not already logged" : "Tally") {
                        Text("Statement \(CurrencyFormatter.format(tally.statementOut)). Logged \(CurrencyFormatter.format(tally.loggedOut)). \(tally.matchedCount) matched.")
                        Text("\(pending.count) to add. \(tally.missingFromStatement.count) logged spends are not on the statement.")
                            .foregroundStyle(DesignSystem.textSecondary)
                    }
                }
                if !cards.isEmpty {
                    Section("Recommendation") {
                        Text(voice)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(cards) { card in
                        Section(card.label == "Card" ? "Card" : "Card \(card.label)") {
                            Text("Amount due \(CurrencyFormatter.format(card.amountDue))")
                                .font(.body.weight(.semibold))
                            if card.minimumDue > 0 {
                                Text("Minimum \(CurrencyFormatter.format(card.minimumDue))")
                                    .foregroundStyle(DesignSystem.textSecondary)
                            }
                            if let dueOn = card.dueOn {
                                Text("Pay by \(dueOn.formatted(date: .abbreviated, time: .omitted))")
                                    .foregroundStyle(DesignSystem.textSecondary)
                            }
                            ForEach(card.groups) { group in
                                HStack {
                                    Text(group.title)
                                    Spacer()
                                    Text(CurrencyFormatter.format(group.amount))
                                }
                                .accessibilityElement(children: .combine)
                            }
                            ForEach(card.merchants) { merchant in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(merchant.note)
                                        Text(merchant.kind == .need ? "Need" : "Extra")
                                            .font(.subheadline)
                                            .foregroundStyle(DesignSystem.textSecondary)
                                    }
                                    Spacer()
                                    Text(CurrencyFormatter.format(merchant.amount))
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                    Section {
                        Button(working ? "Saving" : (cards.count > 1 ? "Save these card bills" : (cards[0].alreadyPlanned ? "Update the card bill" : "Save as the card bill"))) { applyCard() }
                            .disabled(working || cards.allSatisfy { $0.amountDue <= 0 })
                            .frame(minHeight: 44)
                    }
                }
                if !resultText.isEmpty {
                    Section {
                        Text(resultText)
                    }
                }
                if analysis != nil {
                    Section {
                        Button(working ? "Saving" : "Apply suggestion") { apply() }
                            .disabled(working || (pending.isEmpty && selectedCharges.isEmpty))
                            .frame(minHeight: 44)
                    }
                }
            }
            .navigationTitle(cardStatement ? "Card statement" : (openingHistory ? "Import 6 months" : "Last month"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .fileImporter(isPresented: $showPicker, allowedContentTypes: fileTypes, allowsMultipleSelection: true) { result in
                handle(result)
            }
        }
        .presentationDetents([.large])
    }

    private func visibleMonths(_ analysis: StatementAnalysis) -> [StatementMonthTotal] {
        guard !openingHistory, let tally else { return analysis.months }
        let parts = Calendar.current.dateComponents([.year, .month], from: tally.periodStart)
        return analysis.months.filter { $0.year == parts.year && $0.month == parts.month }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selectedCharges.contains(id) },
            set: { selected in
                if selected { selectedCharges.insert(id) } else { selectedCharges.remove(id) }
            }
        )
    }

    private func monthLabel(_ month: StatementMonthTotal) -> String {
        var parts = DateComponents()
        parts.year = month.year
        parts.month = month.month
        parts.day = 1
        let date = Calendar.current.date(from: parts) ?? Date()
        return date.formatted(.dateTime.month(.wide).year())
    }

    private func handle(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorText = error.localizedDescription
        case .success(let urls):
            queued = urls.compactMap(readBytes)
            password = ""
            askPassword = false
            passwordNote = ""
            guard !queued.isEmpty else {
                errorText = "Could not read that file. Use a PDF, Excel, or text statement."
                return
            }
            Task { await openQueued(password: nil) }
        }
    }

    private func readBytes(_ url: URL) -> QueuedStatement? {
        guard url.startAccessingSecurityScopedResource() else { return nil }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return QueuedStatement(name: url.lastPathComponent, data: data)
    }

    private func openQueued(password: String?) async {
        working = true
        errorText = ""
        defer { working = false }
        var pieces: [String] = []
        var locked = false
        var wrong = false
        for file in queued {
            switch openOne(file, password: password) {
            case .text(let text):
                pieces.append(text)
            case .needsPassword:
                locked = true
            case .wrongPassword:
                wrong = true
            case .unrecognized:
                break
            }
        }
        if locked || wrong {
            askPassword = true
            passwordNote = wrong
                ? "That password did not open the file. Try the password the bank uses."
                : "This statement is locked. Enter the password you use to open it."
            return
        }
        askPassword = false
        self.password = ""
        let text = pieces.joined(separator: "\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorText = "Could not read that file. Use a PDF, Excel, or text statement."
            return
        }
        await readStatement(text)
    }

    private func openOne(_ file: QueuedStatement, password: String?) -> StatementFileRead {
        if file.data.starts(with: Data("%PDF".utf8)) {
            return readPDF(file.data, password: password)
        }
        let opened = StatementWorkbook.read(data: file.data, name: file.name, password: password)
        if case .unrecognized = opened, let text = String(data: file.data, encoding: .utf8), !text.isEmpty {
            return .text(text)
        }
        return opened
    }

    private func readPDF(_ data: Data, password: String?) -> StatementFileRead {
        guard let document = PDFDocument(data: data) else { return .unrecognized }
        if document.isLocked {
            let typed = password?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !typed.isEmpty else { return .needsPassword }
            guard document.unlock(withPassword: typed), !document.isLocked else { return .wrongPassword }
        }
        let laidOut = StatementPageLayout.csv(pages: (0..<document.pageCount).compactMap { index in
            document.page(at: index).map(statementGlyphs(on:))
        })
        let laidOutLines = MoneyStatementEngine.parse(text: laidOut, calendar: Calendar.current)
        if laidOutLines.count >= 3 {
            return .text(laidOut)
        }
        let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .unrecognized : .text(text)
    }

    private func statementGlyphs(on page: PDFPage) -> [StatementGlyph] {
        let source = (page.string ?? "") as NSString
        var glyphs: [StatementGlyph] = []
        glyphs.reserveCapacity(source.length)
        for index in 0..<source.length {
            let range = NSRange(location: index, length: 1)
            guard let selection = page.selection(for: range) else { continue }
            let bounds = selection.bounds(for: page)
            guard let character = source.substring(with: range).first else { continue }
            glyphs.append(StatementGlyph(x: bounds.origin.x, y: bounds.origin.y, character: character))
        }
        return glyphs
    }

    private func readStatement(_ text: String) async {
        working = true
        errorText = ""
        resultText = ""
        anomalies = []
        cards = []
        defer { working = false }
        let calendar = Calendar.current
        if cardStatement {
            let refs = modulesVM.bills.filter { FixedExpenseSection.matching($0.category) == .creditCard }.map {
                CardBillRef(title: $0.title, notes: $0.notes, amount: $0.amount)
            }
            let parsed = MoneyStatementEngine.readHDFCCardStatements(text: text, calendar: calendar)
            if !parsed.isEmpty {
                var reports: [CardStatementReport] = []
                for card in parsed {
                    let labeled = await MoneyPhraseService.classifyStatement(card.lines)
                    var copy = card
                    copy.lines = labeled
                    if let report = MoneyStatementEngine.analyseCard(copy, existing: refs, calendar: calendar) {
                        reports.append(report)
                    }
                }
                guard !reports.isEmpty else {
                    errorText = "No card charges were found in that file."
                    return
                }
                cards = reports
                voice = await phraseCards(reports)
                return
            }
        }
        var lines = MoneyStatementEngine.parse(text: text, calendar: calendar)
        if lines.count < 3, let table = await MoneyPhraseService.statementTable(from: text) {
            let extracted = MoneyStatementEngine.parse(text: table, calendar: calendar)
            let digits = text.filter(\.isNumber)
            lines = extracted.filter { digits.contains(String(Int($0.amount.rounded()))) }
        }
        guard !lines.isEmpty else {
            errorText = "No transactions were found. Use a PDF, Excel, or text file that includes dates and amounts."
            analysis = nil
            tally = nil
            cards = []
            pending = []
            anomalies = []
            return
        }
        let labeled = await MoneyPhraseService.classifyStatement(lines)
        if cardStatement {
            let existing = modulesVM.bills.filter { FixedExpenseSection.matching($0.category) == .creditCard }.map(\.amount)
            guard let report = MoneyStatementEngine.analyseCard(lines: labeled, existingCardBills: existing) else {
                errorText = "No card charges were found in that file."
                return
            }
            cards = [report]
            voice = await phraseCards([report])
            return
        }
        let report = MoneyStatementEngine.analyse(lines: labeled, calendar: calendar)
        let check = MoneyStatementEngine.tally(lines: openingHistory ? report.lines : labeled, expenses: modulesVM.dailyExpenses, now: Date(), calendar: calendar)
        let checks = MoneyStatementEngine.anomalies(lines: report.lines, bills: modulesVM.bills, calendar: calendar)
        analysis = report
        tally = check
        anomalies = checks
        pending = openingHistory ? unlogged(report.lines) : check.missingFromLog
        selectedCharges = Set(report.repeating.map(\.id))
        voice = "\(report.sentence) \(check.sentence)"
        voice = await MoneyPhraseService.phraseStatement(analysis: report, tally: check, questions: checks.map(\.question))
    }

    private func unlogged(_ lines: [StatementLine]) -> [StatementLine] {
        let calendar = Calendar.current
        var used = Set<String>()
        return lines.filter { line in
            guard line.direction == .moneyOut else { return false }
            if let match = modulesVM.dailyExpenses.first(where: { !used.contains($0.id) && MoneyStatementEngine.sameSpend($0, line, calendar: calendar) }) {
                used.insert(match.id)
                return false
            }
            return true
        }
    }

    private func confirmSubscription(_ item: StatementAnomaly) {
        anomalies.removeAll { $0.id == item.id }
        pending.removeAll { line in
            line.note.localizedCaseInsensitiveContains(item.note) || item.note.localizedCaseInsensitiveContains(line.note)
        }
        Task {
            await modulesVM.addBill(
                title: item.note,
                amount: item.amount,
                dueDate: Date(),
                category: FixedExpenseSection.subscriptions.rawValue,
                notes: item.note
            )
        }
    }

    private func phraseCards(_ reports: [CardStatementReport]) async -> String {
        var spoken: [String] = []
        for report in reports {
            spoken.append(await MoneyPhraseService.phraseCard(report))
        }
        return spoken.joined(separator: "\n\n")
    }

    private func applyCard() {
        let reports = cards
        guard !reports.isEmpty else { return }
        working = true
        Task {
            for report in reports {
                await modulesVM.applyCardStatement(amount: report.amountDue, label: report.label, dueOn: report.dueOn)
            }
            let names = reports.map { report in
                let name = report.label == "Card" ? "the card" : "card \(report.label)"
                return "\(name) \(CurrencyFormatter.format(report.amountDue))"
            }
            resultText = "Saved \(names.joined(separator: ", ")). The swipes stay off the spend log."
            working = false
        }
    }

    private func apply() {
        working = true
        let lines = pending
        let charges = analysis?.repeating.filter { selectedCharges.contains($0.id) } ?? []
        Task {
            let added = await modulesVM.addImportedSpends(lines, userId: userId)
            var billsAdded = 0
            for charge in charges where openingHistory {
                let exists = modulesVM.bills.contains { bill in
                    FixedExpenseSection.matching(bill.category) == charge.section && abs(bill.amount - charge.amount) < 1
                }
                guard !exists else { continue }
                await modulesVM.addBill(
                    title: charge.section == .emi ? charge.note : charge.section.rawValue,
                    amount: charge.amount,
                    dueDate: dueDate(day: charge.dueDay, section: charge.section),
                    category: charge.section.rawValue,
                    notes: charge.section == .emi ? charge.note : ""
                )
                billsAdded += 1
            }
            var setPay = false
            if let salary = analysis?.salaryCandidate, openingHistory, (modulesVM.moneyPlan?.monthlySalary ?? 0) <= 0 {
                await modulesVM.saveSalary(amount: salary, payday: 1, goalName: "Savings", userId: userId)
                setPay = true
            }
            var summary = "Added \(added) spends"
            if billsAdded > 0 { summary += " and \(billsAdded) bills" }
            if setPay { summary += ". Pay set from the salary credit" }
            resultText = summary + "."
            pending = []
            selectedCharges = []
            working = false
        }
    }

    private func dueDate(day: Int, section: FixedExpenseSection) -> Date {
        let calendar = Calendar.current
        let base = section == .creditCard
            ? (calendar.date(byAdding: .month, value: 1, to: Date()) ?? Date())
            : Date()
        var parts = calendar.dateComponents([.year, .month], from: base)
        parts.day = min(28, max(1, day))
        return calendar.date(from: parts) ?? base
    }
}
