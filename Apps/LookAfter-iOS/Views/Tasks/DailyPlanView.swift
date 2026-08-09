import Combine
import SwiftUI
#if os(iOS)

#if canImport(UIKit)
import UIKit
#endif
import LookAfterAI
import LookAfterCore
import LookAfterFeatures
import LookAfterData

/// A daily time-blocking surface that turns a short task list into a focused plan.
struct DailyPlanView: View {
    let userId: String

    @StateObject private var viewModel: DailyPlannerViewModel
    @State private var isShowingAddTask = false
    @State private var taskToFocus: LifeTask?
    @State private var showReschedulePreview = false

    init(userId: String) {
        self.userId = userId
        _viewModel = StateObject(wrappedValue: DailyPlannerViewModel())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PremiumBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        hero

                        if let message = viewModel.message {
                            Label(message, systemImage: "sparkles")
                                .font(.system(size: 13, weight: .medium, design: .default))
                                .foregroundColor(DesignSystem.textSecondary)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.07)))
                        }

                        if let error = viewModel.error {
                            Text(error)
                                .font(.footnote)
                                .foregroundColor(DesignSystem.error)
                        }

                        if viewModel.isLoading {
                            ProgressView("Loading today's plan…")
                                .tint(DesignSystem.accentPrimary)
                                .frame(maxWidth: .infinity, minHeight: 180)
                        } else if viewModel.todayTasks.isEmpty {
                            emptyState
                        } else {
                            VStack(spacing: 12) {
                                ForEach(viewModel.todayTasks) { task in
                                    DailyPlanTaskCard(task: task) {
                                        taskToFocus = task
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Today’s Plan")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { isShowingAddTask = true }, label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(DesignSystem.textMuted)
                    })
                    .accessibilityLabel("Add a task for today")
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu(content: {
                        Button(action: {
                            Task { await proposeReplan() }
                        }, label: {
                            Label("Adjust schedule", systemImage: "sparkles")
                        })
                        .disabled(viewModel.isScheduling)
                        .accessibilityLabel("Adjust schedule")
                    }, label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(DesignSystem.textSecondary)
                    })
                    .accessibilityLabel("Day planning actions")
                }
            }
        }
        .sheet(isPresented: $showReschedulePreview) {
            if let proposal = viewModel.rescheduleProposal {
                ReschedulePreviewSheet(plannerVM: viewModel, proposal: proposal, userId: userId)
            }
        }
        .onChange(of: viewModel.rescheduleProposal?.id) { _, newID in
            showReschedulePreview = newID != nil
        }
        .sheet(isPresented: $isShowingAddTask) {
            AddDailyTaskSheet { title, minutes, priority, recurrence in
                Task {
                    await viewModel.addTask(
                        title: title,
                        minutes: minutes,
                        priority: priority,
                        recurrence: recurrence,
                        userId: userId
                    )
                }
            }
        }
        .fullScreenCover(item: $taskToFocus) { task in
            VisualFocusTimer(task: task) {
                Task {
                    await viewModel.complete(task)
                    taskToFocus = nil
                }
            }
        }
        .task {
            await viewModel.loadToday(userId: userId)
        }
        .accessibilityIdentifier("screen-daily-plan")
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Date().formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(.system(size: 14, weight: .bold, design: .default))
                .foregroundColor(DesignSystem.textMuted)

            Text("Give today a shape.")
                .font(.system(size: 28, weight: .bold, design: .default))
                .foregroundColor(DesignSystem.textPrimary)

            Text("Add what matters, then let the AI planner place focused time blocks. You can always start the visual timer from any task.")
                .font(.system(size: 15, design: .default))
                .foregroundColor(DesignSystem.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: {
                Task { await proposeReplan() }
            }, label: {
                HStack {
                    if viewModel.isScheduling { ProgressView().tint(.white) }
                    Image(systemName: "sparkles")
                    Text(viewModel.isScheduling ? "Planning…" : "Adjust schedule")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 16, weight: .bold, design: .default))
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 15)
                .background(Capsule().fill(DesignSystem.accentGradient))
            })
            .disabled(viewModel.isScheduling || viewModel.todayTasks.isEmpty)
        }
        .elevatedSurface(padding: 20, cornerRadius: 24)
    }

    private func proposeReplan() async {
        let healthContext = BackgroundAnalyticsService.shared.cachedAIContext(userId: userId)?.promptBlock
        await viewModel.proposeDayReschedule(userId: userId, healthContext: healthContext)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 44))
                .foregroundColor(DesignSystem.textMuted)
            Text("Nothing planned yet")
                .font(.system(size: 18, weight: .bold, design: .default))
                .foregroundColor(DesignSystem.textPrimary)
            Text("Add the first task you want to protect time for today.")
                .font(.system(size: 14, design: .default))
                .multilineTextAlignment(.center)
                .foregroundColor(DesignSystem.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }
}

private struct DailyPlanTaskCard: View {
    let task: LifeTask
    let onStart: () -> Void

    private var color: Color { DesignSystem.textMuted }

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.spacingMD) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(width: 5)
                .frame(minHeight: 44)

            VStack(alignment: .leading, spacing: DesignSystem.spacingXS) {
                Text(task.scheduledTime?.timeString ?? "Unscheduled")
                    .font(.dsCaption(weight: .bold))
                    .foregroundColor(color)
                    .dsChipText()

                Text(task.title)
                    .font(.dsHeadline())
                    .foregroundColor(DesignSystem.textPrimary)
                    .dsPrimaryText(lineLimit: 2)

                MetadataTagRow(tags: task.metadataTags())
            }
            .layoutPriority(1)

            Button(action: onStart) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .minTouchTarget(42)
                    .background(Circle().fill(color))
            }
            .accessibilityLabel("Start \(task.title)")
            .layoutPriority(0)
        }
        .padding(DesignSystem.spacingMD)
        .elevatedSurface(padding: 0, cornerRadius: DesignSystem.radiusLG)
    }
}

private struct AddDailyTaskSheet: View {
    let onAdd: (String, Int, Priority, TaskRecurrence) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var minutes = 30
    @State private var priority: Priority = .medium
    @State private var recurrence: TaskRecurrence = .none

    var body: some View {
        NavigationStack {
            PremiumForm {
                Section("Task") {
                    TextField("What do you want to do?", text: $title)
                    Stepper("\(minutes) minutes", value: $minutes, in: 1...240, step: 1)
                }
                Section("Plan") {
                    Picker("Priority", selection: $priority) {
                        ForEach(Priority.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Repeat", selection: $recurrence) {
                        ForEach(TaskRecurrence.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
            }
            .navigationTitle("Add to Today")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(title.trimmingCharacters(in: .whitespacesAndNewlines), minutes, priority, recurrence)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .keyboardDismissToolbar(label: "Done")
        }
    }
}

/// A distraction-free, landscape-friendly visual timer for the current task.
private struct VisualFocusTimer: View {
    let task: LifeTask
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var remainingSeconds: Int
    @State private var isRunning = true
    /// Cancellable task tick (PERF-007) — no autoconnect Timer after dismiss.
    @State private var tickTask: Task<Void, Never>?

    init(task: LifeTask, onComplete: @escaping () -> Void) {
        self.task = task
        self.onComplete = onComplete
        _remainingSeconds = State(initialValue: task.estimatedMinutes * 60)
    }

    private var totalSeconds: Int { task.estimatedMinutes * 60 }
    private var progress: Double { 1 - Double(remainingSeconds) / Double(max(totalSeconds, 1)) }
    private var accent: Color { DesignSystem.accentPrimary }
    private var remainingString: String {
        String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                PremiumBackground()

                Circle()
                    .fill(accent.opacity(0.28))
                    .frame(width: geometry.size.width * 0.75)
                    .blur(radius: 75)
                    .offset(x: geometry.size.width * 0.28, y: -geometry.size.height * 0.30)

                Group {
                    if geometry.size.width > geometry.size.height {
                        HStack(spacing: 56) { timerRing; taskControls }
                    } else {
                        VStack(spacing: 34) { timerRing; taskControls }
                    }
                }
                .padding(28)
            }
        }
        .statusBarHidden()
        .onAppear {
            requestOrientation(.landscape)
            restartTickerIfNeeded()
        }
        .onChange(of: isRunning) { _, running in
            if running { restartTickerIfNeeded() } else { tickTask?.cancel(); tickTask = nil }
        }
        .onDisappear {
            tickTask?.cancel()
            tickTask = nil
            requestOrientation(.allButUpsideDown)
        }
    }

    private func restartTickerIfNeeded() {
        tickTask?.cancel()
        guard isRunning else { return }
        tickTask = Task { @MainActor in
            while !Task.isCancelled, isRunning, remainingSeconds > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, isRunning else { return }
                remainingSeconds -= 1
                if remainingSeconds == 0 {
                    isRunning = false
                    onComplete()
                    return
                }
            }
        }
    }

    private var timerRing: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.15), lineWidth: 20)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    accent,
                    style: StrokeStyle(lineWidth: 20, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: progress)
            VStack(spacing: 4) {
                Text(remainingString)
                    .font(.system(size: 54, weight: .bold, design: .default).monospacedDigit())
                    .foregroundColor(.white)
                Text(isRunning ? "WORKING" : "PAUSED")
                    .font(.system(size: 12, weight: .bold, design: .default))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .frame(width: 270, height: 270)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(remainingString) remaining")
    }

    private var taskControls: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("NOW")
                .font(.system(size: 12, weight: .bold, design: .default))
                .tracking(2)
                .foregroundColor(.white.opacity(0.62))
            Text(task.title)
                .font(.system(size: 30, weight: .bold, design: .default))
                .foregroundColor(.white)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Text("One thing. No need to rush.")
                .font(.system(size: 16, design: .default))
                .foregroundColor(.white.opacity(0.76))

            HStack(spacing: 12) {
                Button(action: { isRunning.toggle() }, label: {
                    Label(isRunning ? "Pause" : "Resume", systemImage: isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold, design: .default))
                        .foregroundColor(DesignSystem.backgroundPrimary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(.white))
                })
                Button(action: { dismiss() }, label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 46, height: 46)
                        .background(Circle().stroke(Color.white.opacity(0.45), lineWidth: 1))
                })
                .accessibilityLabel("Close timer")
            }

            Button("Mark complete") { onComplete() }
                .font(.system(size: 14, weight: .bold, design: .default))
                .foregroundColor(.white.opacity(0.85))
        }
        .frame(maxWidth: 410, alignment: .leading)
    }

    private func requestOrientation(_ orientations: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations))
    }
}
#endif
