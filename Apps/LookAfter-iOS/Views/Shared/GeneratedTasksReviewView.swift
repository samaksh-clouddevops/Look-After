import SwiftUI
import LookAfterCore
import LookAfterFeatures

/// Review AI-generated starter tasks — toggle, edit, or remove before continuing.
struct GeneratedTasksReviewView: View {
    @ObservedObject var tasksVM: TasksViewModel
    @Binding var keptTaskIDs: Set<String>

    @State private var editingTask: LifeTask?

    private var reviewableTasks: [LifeTask] {
        Self.reviewableTasks(from: tasksVM.tasks)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if reviewableTasks.isEmpty {
                Text("No tasks were generated yet. You can add your own from Today anytime.")
                    .font(.system(size: 13))
                    .foregroundColor(DesignSystem.textMuted)
            } else {
                Text("Uncheck anything you don't want. Tap a task to edit title, time, or duration.")
                    .font(.system(size: 13))
                    .foregroundColor(DesignSystem.textMuted)

                ForEach(reviewableTasks) { task in
                    reviewRow(task)
                }
            }
        }
        .onAppear(perform: seedKeptIDsIfNeeded)
        .onChange(of: tasksVM.tasks.map(\.id)) { _, _ in
            syncKeptIDsWithReviewableTasks()
        }
        .sheet(item: $editingTask) { task in
            QuickTaskEditSheet(
                tasksVM: tasksVM,
                task: task,
                onMoreOptions: { _ in }
            )
        }
        .accessibilityIdentifier("generated-tasks-review")
    }

    @ViewBuilder
    private func reviewRow(_ task: LifeTask) -> some View {
        Button {
            editingTask = task
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { keptTaskIDs.contains(task.id) },
                        set: { isOn in
                            if isOn {
                                keptTaskIDs.insert(task.id)
                            } else {
                                keptTaskIDs.remove(task.id)
                            }
                        }
                    )
                )
                .labelsHidden()
                .tint(DesignSystem.accentPrimary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(DesignSystem.textPrimary)
                        .multilineTextAlignment(.leading)

                    MetadataTagRow(tags: task.metadataTags(timeLabel: scheduleLabel(for: task)))
                }

                Spacer(minLength: 0)

                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DesignSystem.textMuted)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(DesignSystem.backgroundElevated))
        }
        .buttonStyle(.plain)
    }

    private func seedKeptIDsIfNeeded() {
        guard keptTaskIDs.isEmpty else { return }
        keptTaskIDs = Set(reviewableTasks.map(\.id))
    }

    private func syncKeptIDsWithReviewableTasks() {
        let valid = Set(reviewableTasks.map(\.id))
        keptTaskIDs = keptTaskIDs.intersection(valid)
        if keptTaskIDs.isEmpty, !valid.isEmpty {
            keptTaskIDs = valid
        }
    }

    private func scheduleLabel(for task: LifeTask) -> String? {
        let day = Calendar.current.startOfDay(for: task.scheduledDate ?? Date())
        switch TaskScheduleInterval.displaySchedule(for: task, on: day) {
        case .unslottedFlexible:
            return "Flexible · \(task.estimatedMinutes)m"
        case .window(_, _, let rangeLabel):
            return rangeLabel
        case .noSchedule:
            if task.schedulingModeValue == .flexible {
                return "Flexible · \(task.estimatedMinutes)m"
            }
            return nil
        }
    }

    static func reviewableTasks(from tasks: [LifeTask]) -> [LifeTask] {
        tasks
            .filter { task in
                guard task.status.isActive else { return false }
                return task.tags.contains("onboarding")
                    || task.isLifeCommitmentTask
                    || task.tags.contains("daily-routine")
            }
            .sorted { lhs, rhs in
                switch (lhs.scheduledTime, rhs.scheduledTime) {
                case let (l?, r?):
                    return l < r
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
            }
    }

    @MainActor
    static func applySelections(keptIDs: Set<String>, tasksVM: TasksViewModel) async {
        let reviewable = reviewableTasks(from: tasksVM.tasks)
        for task in reviewable where !keptIDs.contains(task.id) {
            _ = await tasksVM.deleteTask(task)
        }
    }
}

/// Full-screen sheet wrapper for post-recompile review in Settings.
struct GeneratedTasksReviewSheet: View {
    @ObservedObject var tasksVM: TasksViewModel
    let userId: String
    let onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var keptTaskIDs: Set<String> = []
    @State private var isApplying = false

    var body: some View {
        NavigationStack {
            ZStack {
                PremiumBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSystem.spacingLG) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Review your day")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(DesignSystem.textPrimary)
                            Text("Your brain created these tasks. Keep what fits — edit or remove the rest.")
                                .font(.system(size: 14))
                                .foregroundColor(DesignSystem.textSecondary)
                        }

                        GeneratedTasksReviewView(tasksVM: tasksVM, keptTaskIDs: $keptTaskIDs)

                        Button(action: confirm) {
                            HStack {
                                Spacer()
                                if isApplying {
                                    ProgressView()
                                        .tint(DesignSystem.accentOnPrimary)
                                } else {
                                    Text("Looks good")
                                        .font(.system(size: 15, weight: .semibold))
                                }
                                Spacer()
                            }
                            .foregroundColor(DesignSystem.accentOnPrimary)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: DesignSystem.radiusFloating, style: .continuous)
                                    .fill(DesignSystem.accentPrimary)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isApplying)
                    }
                    .padding(DesignSystem.spacingLG)
                }
            }
            .navigationTitle("Review tasks")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        onFinished()
                        dismiss()
                    }
                    .disabled(isApplying)
                }
            }
        }
    }

    @MainActor
    private func confirm() {
        isApplying = true
        Task { @MainActor in
            await GeneratedTasksReviewView.applySelections(keptIDs: keptTaskIDs, tasksVM: tasksVM)
            isApplying = false
            onFinished()
            dismiss()
        }
    }
}
