import SwiftUI
import LookAfterCore
import LookAfterAI
import LookAfterData
import LookAfterFeatures

/// macOS-optimized Content View with 3-column layout.
struct MacContentView: View {
    
    @StateObject private var brain: ExecutiveBrain
    @StateObject private var brainVM: BrainViewModel
    @StateObject private var tasksVM: TasksViewModel
    @StateObject private var inboxVM: InboxViewModel
    @StateObject private var adhdVM = ADHDViewModel()
    @StateObject private var macTracker = MacProductivityTracker()
    @StateObject private var firebase = FirebaseManager.shared
    
    @State private var selectedSection: NavigationSection? = .brain
    
    enum NavigationSection: String, CaseIterable, Identifiable {
        case brain = "Brain Dashboard"
        case inbox = "Universal Inbox"
        case tasks = "Task Management"
        case health = "Health & Energy"
        case coach = "Ask anything"
        case settings = "Settings"
        
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .brain: return "brain.head.profile"
            case .inbox: return "tray.fill"
            case .tasks: return "checklist"
            case .health: return "heart.fill"
            case .coach: return "bubble.left.and.bubble.right.fill"
            case .settings: return "gearshape.fill"
            }
        }
    }
    
    init() {
        let glm = GLMService.shared
        let brain = ExecutiveBrain(glmService: glm)
        let decomposer = TaskDecomposer(glmService: glm)

        _brain = StateObject(wrappedValue: brain)
        _brainVM = StateObject(wrappedValue: BrainViewModel(brain: brain))
        _tasksVM = StateObject(wrappedValue: TasksViewModel(decomposer: decomposer))
        _inboxVM = StateObject(wrappedValue: InboxViewModel(glmService: glm))
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            List(NavigationSection.allCases, selection: $selectedSection) { section in
                NavigationLink(value: section) {
                    Label(section.rawValue, systemImage: section.icon)
                        .font(.system(size: 14, weight: .medium, design: .default))
                }
            }
            .navigationTitle(UserFacingCopy.productName)
            .listStyle(.sidebar)
        } detail: {
            // Detail view based on selected section
            ZStack {
                switch selectedSection {
                case .brain:
                    BrainDashboardView(
                        brainVM: brainVM,
                        adhdVM: adhdVM,
                        userId: firebase.currentUserId ?? "",
                        onStartHero: { task in
                            if let task {
                                adhdVM.startCountdown(for: task) {
                                    adhdVM.startFocusSession(task: task)
                                }
                            }
                        },
                        onRescheduleHero: { _ in },
                        onDecideForMe: {},
                        onCapture: {},
                        onResume: { _ in },
                        onMarkMedicationTaken: { medID in
                            var medications = MedicationStore.load()
                            guard let index = medications.firstIndex(where: { $0.id == medID }) else { return }
                            medications[index].isTaken = true
                            medications[index].lastTakenAt = Date()
                            MedicationStore.save(medications)
                        },
                        onNavigateToTasks: { selectedSection = .tasks },
                        onNavigateToCoach: { selectedSection = .coach },
                        onRefresh: {
                            await brainVM.refresh(userId: firebase.currentUserId ?? "")
                        }
                    )
                case .inbox:
                    InboxView(inboxVM: inboxVM, userId: firebase.currentUserId ?? "")
                case .tasks:
                    TaskListView(tasksVM: tasksVM, adhdVM: adhdVM, userId: firebase.currentUserId ?? "")
                case .health:
                    BrainDashboardView(
                        brainVM: brainVM,
                        adhdVM: adhdVM,
                        userId: firebase.currentUserId ?? "",
                        onStartHero: { task in
                            if let task {
                                adhdVM.startCountdown(for: task) {
                                    adhdVM.startFocusSession(task: task)
                                }
                            }
                        },
                        onRescheduleHero: { _ in },
                        onDecideForMe: {},
                        onCapture: {},
                        onResume: { _ in },
                        onMarkMedicationTaken: { medID in
                            var medications = MedicationStore.load()
                            guard let index = medications.firstIndex(where: { $0.id == medID }) else { return }
                            medications[index].isTaken = true
                            medications[index].lastTakenAt = Date()
                            MedicationStore.save(medications)
                        },
                        onNavigateToTasks: { selectedSection = .tasks },
                        onNavigateToCoach: { selectedSection = .coach },
                        onRefresh: {
                            await brainVM.refresh(userId: firebase.currentUserId ?? "")
                        }
                    )
                case .coach:
                    AICoachView(brain: brain)
                case .settings:
                    MacSettingsView()
                case .none:
                    Text("Select a section from sidebar")
                        .foregroundColor(DesignSystem.textMuted)
                }
                
                // ADHD Overlays
                if adhdVM.isEmergencyMode {
                    EmergencyModeView(adhdVM: adhdVM) { task in
                        adhdVM.startCountdown(for: task) {
                            adhdVM.startFocusSession(task: task)
                        }
                    }
                    .transition(.opacity)
                    .zIndex(100)
                }
                
                if adhdVM.isFocusSessionActive {
                    FocusSessionView(adhdVM: adhdVM)
                        .transition(.opacity)
                        .zIndex(99)
                }
                
                if adhdVM.isBodyDoubling {
                    BodyDoublingView(adhdVM: adhdVM)
                        .transition(.opacity)
                        .zIndex(98)
                }
            }
        }
        .task {
            if !firebase.isAuthenticated {
                try? await firebase.signInAnonymously()
            }
            macTracker.startTracking()
        }
    }
}
