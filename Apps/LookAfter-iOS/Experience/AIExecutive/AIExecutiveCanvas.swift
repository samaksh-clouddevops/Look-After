import SwiftUI
import LookAfterCore
import LookAfterAI
import LookAfterData
import LookAfterFeatures
import LookAfterHealth

/// V2 executive shell — companion sessions, narrative plan, explainable AI.
struct AIExecutiveCanvas: View {
    @EnvironmentObject private var shell: AppShellState

    var body: some View {
        AIExecutiveCanvasBody(
            shell: shell,
            continueSession: shell.continueSession
        )
        .accessibilityIdentifier("screen-ai-executive")
    }
}

/// Observes `ContinueSessionController` directly so presentation updates within 100 ms of Continue.
private struct AIExecutiveCanvasBody: View {
    @ObservedObject var shell: AppShellState
    @ObservedObject var continueSession: ContinueSessionController
    @StateObject private var firebase = FirebaseManager.shared
    @State private var showCapture = false
    @State private var showSettings = false
    @State private var showPlan = false
    @State private var showHealth = false

    private var userId: String { firebase.currentUserId ?? "" }

    var body: some View {
        ZStack {
            ExecutiveTodayView(
                userId: userId,
                onCapture: { showCapture = true },
                onSettings: { showSettings = true },
                onOpenHealth: { showHealth = true },
                onViewPlan: { showPlan = true },
                onOpenContinueSession: { context in
                    HapticManager.impact(.medium)
                    continueSession.open(context: context)
                }
            )

            executiveOverlays
        }
        .sheet(isPresented: $showCapture) {
            ExecutiveCaptureSheet(userId: userId)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(.clear)
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    .environmentObject(shell)
            }
        }
        .sheet(isPresented: $showPlan) {
            if let story = shell.contextOrchestrator.briefing?.todaysStory {
                TodaysStoryView(story: story)
                    .presentationBackground(.clear)
            }
        }
        .sheet(isPresented: $showHealth) {
            HealthDetailView()
                .presentationBackground(.clear)
        }
        .fullScreenCover(isPresented: Binding(
            get: { continueSession.isPresented },
            set: { if !$0 { continueSession.endSession() } }
        )) {
            ContinueSessionView(
                controller: continueSession,
                onOpenHealth: { showHealth = true },
                onDone: {
                    continueSession.endSession()
                    Task { await shell.refreshContext(userId: userId) }
                }
            )
        }
        .fullScreenCover(isPresented: Binding(
            get: { !firebase.isAuthenticated },
            set: { _ in }
        )) {
            AuthView()
        }
        .onChange(of: shell.tasksVM.completedToday.count) { oldCount, newCount in
            guard newCount > oldCount, let task = shell.tasksVM.completedToday.last else { return }
            Task {
                await shell.brainVM.handleTaskCompleted(task, userId: userId)
                shell.refreshWidgetData()
            }
        }
    }

    @ViewBuilder
    private var executiveOverlays: some View {
        if shell.adhdVM.isEmergencyMode {
            EmergencyModeView(adhdVM: shell.adhdVM) { task in
                openCompanionSession(for: task)
            }
            .transition(.opacity)
            .zIndex(100)
        }
    }

    private func openCompanionSession(for task: LifeTask) {
        guard let snapshot = shell.contextOrchestrator.snapshot else { return }
        let estimate = DurationEstimator().estimate(
            DurationEstimator.Input(task: task, snapshot: snapshot, healthSummary: shell.brainVM.healthSummary)
        )
        let context = ContinueSessionContext(
            workingContext: WorkingContext(kind: .task, title: task.title, taskID: task.id),
            task: task,
            resumeSnapshot: shell.contextOrchestrator.resumeSnapshot,
            durationEstimate: estimate,
            restorationMessage: "Restoring your workspace…",
            restartTaxSeconds: 1
        )
        HapticManager.impact(.medium)
        continueSession.open(context: context)
        shell.adhdVM.deactivateEmergencyMode()
    }
}
