import SwiftUI
import LookAfterCore
import LookAfterFeatures

/// Fast task edits — title, duration, and fixed/flexible timing.
struct QuickTaskEditSheet: View {
    @ObservedObject var tasksVM: TasksViewModel
    let task: LifeTask
    var onMoreOptions: (LifeTask) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var estimatedMinutes: Int
    @State private var estimatedMinutesText: String
    @State private var schedulingMode: TaskSchedulingMode
    @State private var fixedStartTime: Date
    @State private var fixedEndTime: Date
    @State private var saveError: String?
    @State private var isSaving = false

    init(
        tasksVM: TasksViewModel,
        task: LifeTask,
        onMoreOptions: @escaping (LifeTask) -> Void = { _ in }
    ) {
        self.tasksVM = tasksVM
        self.task = task
        self.onMoreOptions = onMoreOptions
        _title = State(initialValue: task.title)
        _estimatedMinutes = State(initialValue: task.estimatedMinutes)
        _estimatedMinutesText = State(initialValue: String(task.estimatedMinutes))
        _schedulingMode = State(initialValue: task.timeConstraintValue.asSchedulingMode)
        let start = task.scheduledTime ?? Date()
        _fixedStartTime = State(initialValue: start)
        _fixedEndTime = State(initialValue: task.scheduledEndTime ?? start.addingTimeInterval(TimeInterval(task.estimatedMinutes * 60)))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PremiumBackground()

                PremiumForm {
                    Section {
                        TextField("Title", text: $title)
                    }

                    Section("Time") {
                        HStack(spacing: 12) {
                            TextField("Minutes", text: $estimatedMinutesText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 72)
                                .onSubmit(commitEstimatedMinutesText)

                            Text("minutes")
                                .foregroundColor(DesignSystem.textMuted)

                            Spacer(minLength: 0)

                            Stepper("", value: $estimatedMinutes, in: 1...240)
                                .labelsHidden()
                        }
                    }

                    Section("When") {
                        Picker("Type", selection: $schedulingMode) {
                            ForEach(TaskSchedulingMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }

                        if schedulingMode == .fixedTime {
                            DatePicker("Start", selection: $fixedStartTime, displayedComponents: .hourAndMinute)
                            DatePicker("End", selection: $fixedEndTime, displayedComponents: .hourAndMinute)
                        }
                    }

                    if let saveError {
                        Section {
                            Text(saveError)
                                .font(.system(size: 12))
                                .foregroundColor(DesignSystem.error)
                        }
                    }

                    Section {
                        Button("More options…") {
                            dismiss()
                            onMoreOptions(task)
                        }
                        .foregroundColor(DesignSystem.accentPrimary)

                        Button(role: .destructive) {
                            Task {
                                _ = await tasksVM.deleteTask(task)
                                dismiss()
                            }
                        } label: {
                            Label("Delete task", systemImage: "trash")
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Edit task")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onChange(of: estimatedMinutes) { _, newValue in
                estimatedMinutesText = String(newValue)
            }
            .keyboardDismissToolbar(label: "Done")
        }
    }

    private func commitEstimatedMinutesText() {
        let digits = estimatedMinutesText.filter(\.isNumber)
        guard let value = Int(digits), value >= 1 else {
            estimatedMinutesText = String(estimatedMinutes)
            return
        }
        estimatedMinutes = min(value, 240)
        estimatedMinutesText = String(estimatedMinutes)
    }

    private func save() {
        KeyboardDismiss.dismiss()
        commitEstimatedMinutesText()

        guard schedulingMode != .fixedTime || fixedEndTime > fixedStartTime else {
            saveError = "End time must be after start time."
            return
        }

        isSaving = true
        saveError = nil

        var updated = task
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.estimatedMinutes = estimatedMinutes
        updated.applyUserSchedulingModeEdit(
            schedulingMode,
            fixedStartTime: schedulingMode == .fixedTime ? fixedStartTime : nil,
            fixedEndTime: schedulingMode == .fixedTime ? fixedEndTime : nil
        )

        Task {
            let userId = updated.userId.isEmpty ? task.userId : updated.userId
            await tasksVM.scheduleMutation.persist(
                updated,
                userId: userId,
                userPlaced: schedulingMode == .fixedTime
            )
            isSaving = false
            if tasksVM.error == nil {
                dismiss()
            } else {
                saveError = tasksVM.error
            }
        }
    }
}
