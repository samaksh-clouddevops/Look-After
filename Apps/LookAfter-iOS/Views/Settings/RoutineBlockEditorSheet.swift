import SwiftUI
import LookAfterCore

/// Add/edit sheet for a single `RoutineBlock` — title, days, start time, duration, non-negotiable flag.
struct RoutineBlockEditorSheet: View {
    enum Mode {
        case add
        case edit(RoutineBlock)
    }

    let mode: Mode
    var onSave: (RoutineBlock) -> Void
    var onDelete: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    private enum DurationInputMode: String, CaseIterable, Identifiable {
        case duration = "Duration"
        case endTime = "End time"
        var id: String { rawValue }
    }

    @State private var title: String
    @State private var days: WeekdaySet
    @State private var startDate: Date
    @State private var durationMinutes: Int
    @State private var endDate: Date
    @State private var durationInputMode: DurationInputMode = .duration
    @State private var isNonNegotiable: Bool
    @State private var conflictWarning: String?

    private let existingID: String?

    init(mode: Mode, onSave: @escaping (RoutineBlock) -> Void, onDelete: (() -> Void)? = nil) {
        self.mode = mode
        self.onSave = onSave
        self.onDelete = onDelete
        switch mode {
        case .add:
            existingID = nil
            _title = State(initialValue: "")
            _days = State(initialValue: .everyDay)
            let start = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
            _startDate = State(initialValue: start)
            _durationMinutes = State(initialValue: 30)
            _endDate = State(initialValue: start.addingTimeInterval(30 * 60))
            _isNonNegotiable = State(initialValue: true)
        case .edit(let block):
            existingID = block.id
            _title = State(initialValue: block.title)
            _days = State(initialValue: block.days)
            let start = Calendar.current.date(bySettingHour: block.startHour, minute: block.startMinute, second: 0, of: Date()) ?? Date()
            _startDate = State(initialValue: start)
            _durationMinutes = State(initialValue: block.durationMinutes)
            _endDate = State(initialValue: start.addingTimeInterval(Double(block.durationMinutes) * 60))
            _isNonNegotiable = State(initialValue: block.isNonNegotiable)
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Routine block") {
                    TextField("Title (e.g. Gym, Wake up)", text: $title)
                    DatePicker("Start time", selection: $startDate, displayedComponents: .hourAndMinute)

                    Picker("Set by", selection: $durationInputMode) {
                        ForEach(DurationInputMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch durationInputMode {
                    case .duration:
                        Stepper("Duration: \(durationMinutes.durationString)", value: $durationMinutes, in: 5...480, step: 5)
                    case .endTime:
                        DatePicker("End time", selection: $endDate, displayedComponents: .hourAndMinute)
                    }

                    Toggle("Non-negotiable (protect this time)", isOn: $isNonNegotiable)
                }

                Section("Repeats on") {
                    dayToggle("Mon", \.monday)
                    dayToggle("Tue", \.tuesday)
                    dayToggle("Wed", \.wednesday)
                    dayToggle("Thu", \.thursday)
                    dayToggle("Fri", \.friday)
                    dayToggle("Sat", \.saturday)
                    dayToggle("Sun", \.sunday)
                }

                if let conflictWarning {
                    Section {
                        Text(conflictWarning)
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                    }
                }

                if case .edit = mode, let onDelete {
                    Section {
                        Button("Delete Routine Block", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existingID == nil ? "Add Routine Block" : "Edit Routine Block")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: startDate) { _, newValue in
                if durationInputMode == .duration {
                    endDate = newValue.addingTimeInterval(Double(durationMinutes) * 60)
                } else {
                    syncDurationFromEndDate()
                }
                checkConflicts()
            }
            .onChange(of: durationMinutes) { _, newValue in
                endDate = startDate.addingTimeInterval(Double(newValue) * 60)
                checkConflicts()
            }
            .onChange(of: endDate) { _, _ in
                guard durationInputMode == .endTime else { return }
                syncDurationFromEndDate()
                checkConflicts()
            }
            .onChange(of: days) { _, _ in checkConflicts() }
            .onAppear { checkConflicts() }
        }
    }

    private func dayToggle(_ label: String, _ keyPath: WritableKeyPath<WeekdaySet, Bool>) -> some View {
        Toggle(label, isOn: Binding(
            get: { days[keyPath: keyPath] },
            set: { days[keyPath: keyPath] = $0 }
        ))
    }

    private func candidate() -> RoutineBlock {
        let calendar = Calendar.current
        return RoutineBlock(
            id: existingID,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            days: days,
            startHour: calendar.component(.hour, from: startDate),
            startMinute: calendar.component(.minute, from: startDate),
            durationMinutes: durationMinutes,
            isNonNegotiable: isNonNegotiable
        )
    }

    /// Recomputes `durationMinutes` from `startDate`/`endDate`, treating an end time
    /// earlier than the start time as crossing midnight (e.g. 23:00 → 00:30 = 90 min).
    private func syncDurationFromEndDate() {
        let calendar = Calendar.current
        let startMinutes = calendar.component(.hour, from: startDate) * 60 + calendar.component(.minute, from: startDate)
        let endMinutes = calendar.component(.hour, from: endDate) * 60 + calendar.component(.minute, from: endDate)
        var delta = endMinutes - startMinutes
        if delta <= 0 { delta += 24 * 60 }
        durationMinutes = min(max(delta, 5), 480)
    }

    private func checkConflicts() {
        let conflicts = RoutineBlockStore.conflicts(with: candidate())
        conflictWarning = conflicts.isEmpty ? nil :
            "Overlaps with: \(conflicts.map(\.title).joined(separator: ", "))"
    }

    private func save() {
        onSave(candidate())
        dismiss()
    }
}
