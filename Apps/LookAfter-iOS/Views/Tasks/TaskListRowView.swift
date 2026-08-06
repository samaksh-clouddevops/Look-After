import SwiftUI
import LookAfterCore
import LookAfterFeatures

/// Single task row for `TaskListView` — extracted to keep the list body type-checkable.
struct TaskListRowView: View {
    let task: LifeTask
    @ObservedObject var tasksVM: TasksViewModel
    @ObservedObject var adhdVM: ADHDViewModel
    @Binding var editingTask: LifeTask?
    let onComplete: (LifeTask) -> Void
    let onDelete: (LifeTask) -> Void

    var body: some View {
        TaskCardView(
            task: task,
            onOpen: { editingTask = task },
            onComplete: { onComplete(task) },
            onMarkIncomplete: { Task { await tasksVM.markIncomplete(task) } },
            onStart: {
                adhdVM.startCountdown(for: task) {
                    adhdVM.startFocusSession(task: task)
                }
            },
            onDecompose: { Task { await tasksVM.decomposeTask(task) } },
            onEdit: { editingTask = task },
            onDuplicate: { tasksVM.duplicateTask(task) },
            onDelete: { onDelete(task) },
            isDecomposing: tasksVM.isDecomposing(taskId: task.id),
            timeDisplayLabel: tasksVM.timeDisplay(for: task).lineLabel,
            isLoadingTimeDisplay: tasksVM.isLoadingTimeDisplay(taskId: task.id)
        )
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(
            top: 4,
            leading: DesignSystem.spacingLG,
            bottom: 4,
            trailing: DesignSystem.spacingLG
        ))
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if !task.isCompleted {
                Button(action: { onComplete(task) }, label: {
                    Label("Complete", systemImage: "checkmark.circle")
                })
                .tint(DesignSystem.success)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: { onDelete(task) }, label: {
                Label("Delete", systemImage: "trash")
            })
        }
        .contextMenu { contextMenuButtons }
    }

    @ViewBuilder
    private var contextMenuButtons: some View {
        Button(action: { editingTask = task }, label: {
            Label(task.isCompleted ? "View Details" : "Edit", systemImage: "pencil")
        })

        if task.isCompleted {
            Button(action: { Task { await tasksVM.markIncomplete(task) } }, label: {
                Label("Mark Incomplete", systemImage: "arrow.uturn.backward.circle")
            })
            Button(action: { tasksVM.duplicateTask(task) }, label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            })
        } else {
            Button(action: {
                adhdVM.startCountdown(for: task) {
                    adhdVM.startFocusSession(task: task)
                }
            }, label: {
                Label("Start", systemImage: "play.fill")
            })
            if task.steps.isEmpty {
                Button(action: { Task { await tasksVM.decomposeTask(task) } }, label: {
                    Label("Break Down", systemImage: "square.split.2x2")
                })
            }
            Button(action: { tasksVM.duplicateTask(task) }, label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            })
        }

        Button(role: .destructive, action: { onDelete(task) }, label: {
            Label("Delete", systemImage: "trash")
        })
    }
}
