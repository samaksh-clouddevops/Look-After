import SwiftUI
import LookAfterCore
import LookAfterFeatures

/// Single-Task Card Stack View — displays 1 task at a time with gesture-based completion & deferral.
public struct TaskCardStackView: View {
    
    @ObservedObject var tasksVM: TasksViewModel
    @ObservedObject var adhdVM: ADHDViewModel
    var onTaskDeferred: ((LifeTask) -> Void)?
    var onUndoRequested: ((String) -> Void)?

    @State private var offset: CGSize = .zero
    @State private var editingTask: LifeTask?

    public init(
        tasksVM: TasksViewModel,
        adhdVM: ADHDViewModel,
        onTaskDeferred: ((LifeTask) -> Void)? = nil,
        onUndoRequested: ((String) -> Void)? = nil
    ) {
        self.tasksVM = tasksVM
        self.adhdVM = adhdVM
        self.onTaskDeferred = onTaskDeferred
        self.onUndoRequested = onUndoRequested
    }
    
    var activeTasks: [LifeTask] {
        TaskListSorter.sortForToday(
            tasksVM.tasks.filter { $0.isActionableToday(allTasks: tasksVM.schedulingContext) }
        )
    }
    
    public var body: some View {
        ZStack {
            PremiumBackground()
            
            VStack(spacing: DesignSystem.spacingXL) {
                HStack {
                    TagChipView("\(activeTasks.count) tasks left", icon: "square.stack.3d.up.fill", style: .neutral)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DesignSystem.spacingLG)
                
                Spacer(minLength: 0)
                
                if let currentTask = activeTasks.first {
                    ZStack {
                        if activeTasks.count > 1 {
                            focusCard(for: currentTask)
                                .scaleEffect(0.94)
                                .offset(y: DesignSystem.spacingLG)
                                .opacity(0.5)
                                .allowsHitTesting(false)
                        }
                        
                        focusCard(for: currentTask)
                            .overlay(alignment: .topTrailing) {
                                Menu(content: {
                                    Button(action: { editingTask = currentTask }) {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    Button(action: { tasksVM.duplicateTask(currentTask) }) {
                                        Label("Duplicate", systemImage: "plus.square.on.square")
                                    }
                                    Button(role: .destructive, action: {
                                        deleteTask(currentTask)
                                    }, label: {
                                        Label("Delete", systemImage: "trash")
                                    })
                                }, label: {
                                    Image(systemName: "ellipsis.circle")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(DesignSystem.textMuted)
                                        .minTouchTarget(36)
                                        .padding(DesignSystem.spacingSM)
                                })
                            }
                            .offset(x: offset.width, y: offset.height)
                            .rotationEffect(.degrees(Double(offset.width / 15)))
                            .gesture(
                                DragGesture()
                                    .onChanged { gesture in
                                        offset = gesture.translation
                                    }
                                    .onEnded { gesture in
                                        if gesture.translation.width > 120 {
                                            completeTask(currentTask)
                                        } else if gesture.translation.width < -120 {
                                            deferTask(currentTask)
                                        } else {
                                            withAnimation(.spring()) { offset = .zero }
                                        }
                                    }
                            )
                    }
                    .padding(.horizontal, DesignSystem.spacingXXL)
                } else {
                    EmptyStateView(
                        icon: "party.popper.fill",
                        title: "ALL CLEAR!",
                        subtitle: "You've cleared your focus stack. Take a guilt-free rest!"
                    )
                }
                
                Spacer(minLength: 0)
            }
        }
        .sheet(item: $editingTask) { task in
            TaskFormSheet(tasksVM: tasksVM, mode: .edit(task))
        }
        .undoToast(
            isShowing: Binding(
                get: { tasksVM.isUndoToastVisible },
                set: { if !$0 { tasksVM.clearPendingUndo() } }
            ),
            message: tasksVM.undoToastMessage,
            onUndo: { Task { await tasksVM.performUndo() } },
            onDismiss: { tasksVM.clearPendingUndo() }
        )
        .accessibilityIdentifier("screen-task-card-stack")
    }

    @ViewBuilder
    private func focusCard(for task: LifeTask) -> some View {
        TaskCardView(
            task: task,
            style: .focusStack,
            onOpen: { editingTask = task },
            onComplete: { completeTask(task) },
            onMarkIncomplete: {},
            onStart: {
                adhdVM.startCountdown(for: task) {
                    adhdVM.startFocusSession(task: task)
                }
            },
            onDecompose: {},
            onEdit: { editingTask = task },
            onDuplicate: { tasksVM.duplicateTask(task) },
            onDelete: { deleteTask(task) },
            onDefer: { deferTask(task) }
        )
    }
    
    private func showUndo(_ message: String) {
        onUndoRequested?(message)
    }
    
    private func deleteTask(_ task: LifeTask) {
        HapticManager.notification(.warning)
        withAnimation(.easeOut(duration: 0.3)) {
            offset = CGSize(width: 0, height: -500)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            Task {
                if await tasksVM.deleteTask(task) != nil {
                    showUndo("Task deleted • Undo")
                }
                offset = .zero
            }
        }
    }
    
    private func completeTask(_ task: LifeTask) {
        HapticManager.notification(.success)
        withAnimation(.easeOut(duration: 0.3)) {
            offset = CGSize(width: 500, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            Task {
                if await tasksVM.completeTask(task) != nil {
                    showUndo("Task completed • Undo")
                }
                offset = .zero
            }
        }
    }
    
    private func deferTask(_ task: LifeTask) {
        HapticManager.impact(.medium)
        withAnimation(.easeOut(duration: 0.3)) {
            offset = CGSize(width: -500, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            Task {
                if let idx = tasksVM.tasks.firstIndex(where: { $0.id == task.id }) {
                    let item = tasksVM.tasks.remove(at: idx)
                    tasksVM.tasks.append(item)
                }
                onTaskDeferred?(task)
                offset = .zero
            }
        }
    }
}
