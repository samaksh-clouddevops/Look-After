import SwiftUI
import LookAfterCore
import LookAfterFeatures

/// Single task row for `TaskListView` — extracted to keep the list body type-checkable.
struct TaskListRowView: View {
    let task: LifeTask
    let isDecomposing: Bool
    let timeDisplayLabel: String
    let isLoadingTimeDisplay: Bool
    @Binding var editingTask: LifeTask?
    let onComplete: (LifeTask) -> Void
    let onDelete: (LifeTask) -> Void
    let onMarkIncomplete: () -> Void
    let onStart: () -> Void
    let onDecompose: () -> Void
    let onDuplicate: () -> Void

    var body: some View {
        TaskCardView(
            task: task,
            onOpen: { editingTask = task },
            onComplete: { onComplete(task) },
            onMarkIncomplete: onMarkIncomplete,
            onStart: onStart,
            onDecompose: onDecompose,
            onEdit: { editingTask = task },
            onDuplicate: onDuplicate,
            onDelete: { onDelete(task) },
            isDecomposing: isDecomposing,
            timeDisplayLabel: timeDisplayLabel,
            isLoadingTimeDisplay: isLoadingTimeDisplay
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
            Button(action: onMarkIncomplete, label: {
                Label("Mark Incomplete", systemImage: "arrow.uturn.backward.circle")
            })
            Button(action: onDuplicate, label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            })
        } else {
            Button(action: onStart, label: {
                Label("Start", systemImage: "play.fill")
            })
            if task.steps.isEmpty {
                Button(action: onDecompose, label: {
                    Label("Break Down", systemImage: "square.split.2x2")
                })
            }
            Button(action: onDuplicate, label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            })
        }

        Button(role: .destructive, action: { onDelete(task) }, label: {
            Label("Delete", systemImage: "trash")
        })
    }
}
