import SwiftUI
import Combine
import LookAfterCore

// MARK: - ViewModel

@MainActor
public final class MedicationViewModel: ObservableObject {
    @Published public var medications: [Medication] = []
    private let persistenceKey = "lifeos_medications_list"
    private let resetDateKey = "lifeos_medications_last_reset"
    
    public init() {
        loadFromDisk()
        resetDailyIfNeeded()
    }
    
    /// Reset all taken flags at the start of a new day.
    public func resetDailyIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())
        let lastReset = UserDefaults.standard.object(forKey: resetDateKey) as? Date ?? .distantPast
        let lastResetDay = Calendar.current.startOfDay(for: lastReset)
        
        guard lastResetDay < today else { return }
        
        for idx in medications.indices {
            medications[idx].isTaken = false
        }
        UserDefaults.standard.set(today, forKey: resetDateKey)
        saveToDisk()
    }
    
    public func toggleMedication(_ med: Medication) {
        if let idx = medications.firstIndex(where: { $0.id == med.id }) {
            medications[idx].isTaken.toggle()
            if medications[idx].isTaken {
                medications[idx].lastTakenAt = Date()
                medications[idx].adherenceLog.append(Date())
            }
            saveToDisk()
        }
    }
    
    public func addMedication(_ med: Medication) {
        medications.append(med)
        saveToDisk()
    }
    
    public func updateMedication(_ med: Medication) {
        if let idx = medications.firstIndex(where: { $0.id == med.id }) {
            medications[idx] = med
            saveToDisk()
        }
    }
    
    public func deleteMedication(at offsets: IndexSet) {
        medications.remove(atOffsets: offsets)
        saveToDisk()
    }
    
    public func deleteMedication(_ med: Medication) {
        medications.removeAll { $0.id == med.id }
        saveToDisk()
    }
    
    public var adherenceRate: Double {
        guard !medications.isEmpty else { return 0 }
        let taken = medications.filter(\.isTaken).count
        return Double(taken) / Double(medications.count)
    }
    
    private func saveToDisk() {
        MedicationStore.save(medications)
        NotificationCenter.default.post(name: .medicationListDidChange, object: nil)
    }
    
    private func loadFromDisk() {
        medications = MedicationStore.load()
    }
}

// MARK: - View

public struct MedicationView: View {
    @StateObject private var viewModel = MedicationViewModel()
    @State private var showAddSheet = false
    @State private var editingMedication: Medication?
    
    public init() {}
    
    public var body: some View {
        ZStack {
            PremiumBackground()
            
            VStack(alignment: .leading, spacing: DesignSystem.spacingLG) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Medication & Supplements")
                            .font(.system(size: 28, weight: .bold, design: .default))
                            .foregroundColor(DesignSystem.textPrimary)
                        
                        Text("Track your daily routines and adherence.")
                            .font(.system(size: 15, weight: .medium, design: .default))
                            .foregroundColor(DesignSystem.textSecondary)
                    }
                    Spacer()
                    Button(action: { showAddSheet = true }) {
                        Image(systemName: "plus.circle.fill")
                            .premiumActionIcon(size: 28)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 20)
                
                if !viewModel.medications.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .foregroundColor(DesignSystem.success)
                        Text("Today's Adherence: \(Int(viewModel.adherenceRate * 100))%")
                            .font(.system(size: 13, weight: .semibold, design: .default))
                            .foregroundColor(DesignSystem.textSecondary)
                    }
                    .padding(.horizontal)
                }
                
                if viewModel.medications.isEmpty {
                    EmptyStateView(
                        icon: "pill.fill",
                        title: "No Medications Tracked",
                        subtitle: "Add your daily medications or supplements to track adherence.",
                        actionTitle: "Add Medication",
                        onAction: { showAddSheet = true }
                    )
                } else {
                    List {
                        ForEach(viewModel.medications) { med in
                            medicationRow(med)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive, action: {
                                        viewModel.deleteMedication(med)
                                        HapticManager.notification(.warning)
                                    }, label: {
                                        Label("Delete", systemImage: "trash")
                                    })
                                }
                                .onTapGesture {
                                    editingMedication = med
                                }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .onAppear { viewModel.resetDailyIfNeeded() }
        .sheet(isPresented: $showAddSheet) {
            AddMedicationSheet(viewModel: viewModel)
        }
        .sheet(item: $editingMedication) { med in
            EditMedicationSheet(viewModel: viewModel, medication: med)
        }
    }
    
    @ViewBuilder
    private func medicationRow(_ med: Medication) -> some View {
        HStack(spacing: 16) {
            Button(action: {
                viewModel.toggleMedication(med)
                HapticManager.impact(.light)
            }, label: {
                Image(systemName: med.isTaken ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundColor(med.isTaken ? DesignSystem.success : DesignSystem.textMuted)
            })
            
            VStack(alignment: .leading, spacing: 4) {
                Text(med.name)
                    .font(.system(size: 16, weight: .semibold, design: .default))
                    .foregroundColor(med.isTaken ? DesignSystem.textMuted : DesignSystem.textPrimary)
                    .strikethrough(med.isTaken)
                
                HStack {
                    Text(med.dosage)
                    Text("•")
                    Text(med.scheduledTime.formatted(date: .omitted, time: .shortened))
                }
                .font(.system(size: 13, weight: .medium, design: .default))
                .foregroundColor(DesignSystem.textSecondary)
                
                if !med.adherenceLog.isEmpty {
                    Text("Taken \(med.adherenceLog.count) times")
                        .font(.system(size: 11, weight: .medium, design: .default))
                        .foregroundColor(DesignSystem.textMuted)
                }
            }
            Spacer()
        }
        .padding()
        .elevatedSurface(padding: DesignSystem.spacingMD, cornerRadius: DesignSystem.radiusMD)
    }
}

// MARK: - Add Medication Sheet

struct AddMedicationSheet: View {
    @ObservedObject var viewModel: MedicationViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var dosage = ""
    @State private var scheduledTime = Date()
    @State private var isCreating = false
    
    var body: some View {
        NavigationStack {
            PremiumForm {
                Section("Details") {
                    TextField("Medication Name (e.g. Adderall, Vitamin D)", text: $name)
                    TextField("Dosage (e.g. 20mg, 5000 IU)", text: $dosage)
                }
                Section("Schedule") {
                    DatePicker("Scheduled Time", selection: $scheduledTime, displayedComponents: .hourAndMinute)
                }
            }
            .navigationTitle("Add Medication")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isCreating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: {
                        guard !name.isEmpty else { return }
                        isCreating = true
                        let med = Medication(name: name, dosage: dosage.isEmpty ? "1 dose" : dosage, scheduledTime: scheduledTime)
                        viewModel.addMedication(med)
                        HapticManager.notification(.success)
                        dismiss()
                    }) {
                        if isCreating { ProgressView() } else { Text("Save") }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                }
            }
        }
    }
}

// MARK: - Edit Medication Sheet

struct EditMedicationSheet: View {
    @ObservedObject var viewModel: MedicationViewModel
    let medication: Medication
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String
    @State private var dosage: String
    @State private var scheduledTime: Date
    @State private var isSaving = false
    
    init(viewModel: MedicationViewModel, medication: Medication) {
        self.viewModel = viewModel
        self.medication = medication
        _name = State(initialValue: medication.name)
        _dosage = State(initialValue: medication.dosage)
        _scheduledTime = State(initialValue: medication.scheduledTime)
    }
    
    var body: some View {
        NavigationStack {
            PremiumForm {
                Section("Details") {
                    TextField("Medication Name", text: $name)
                    TextField("Dosage", text: $dosage)
                }
                Section("Schedule") {
                    DatePicker("Scheduled Time", selection: $scheduledTime, displayedComponents: .hourAndMinute)
                }
            }
            .navigationTitle("Edit Medication")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        isSaving = true
                        var updated = medication
                        updated.name = name
                        updated.dosage = dosage
                        updated.scheduledTime = scheduledTime
                        viewModel.updateMedication(updated)
                        HapticManager.notification(.success)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }
}
