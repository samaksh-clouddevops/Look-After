import SwiftUI
import LookAfterCore

/// Unified task card — list and focus-stack layouts share one implementation.
struct TaskCardView: View {
    enum Style {
        case list
        case focusStack
    }

    let task: LifeTask
    let style: Style
    let onOpen: () -> Void
    let onComplete: () -> Void
    let onMarkIncomplete: () -> Void
    let onStart: () -> Void
    let onDecompose: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onDefer: (() -> Void)?
    let isDecomposing: Bool

    @State private var isExpanded = false

    init(
        task: LifeTask,
        style: Style = .list,
        onOpen: @escaping () -> Void,
        onComplete: @escaping () -> Void,
        onMarkIncomplete: @escaping () -> Void,
        onStart: @escaping () -> Void,
        onDecompose: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onDuplicate: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onDefer: (() -> Void)? = nil,
        isDecomposing: Bool = false
    ) {
        self.task = task
        self.style = style
        self.onOpen = onOpen
        self.onComplete = onComplete
        self.onMarkIncomplete = onMarkIncomplete
        self.onStart = onStart
        self.onDecompose = onDecompose
        self.onEdit = onEdit
        self.onDuplicate = onDuplicate
        self.onDelete = onDelete
        self.onDefer = onDefer
        self.isDecomposing = isDecomposing
    }

    private var isCompleted: Bool { task.isCompleted }

    var body: some View {
        switch style {
        case .list:
            listCard
        case .focusStack:
            focusStackCard
        }
    }

    // MARK: - List

    private var listCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                checkboxButton

                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Image(systemName: task.lifeArea.icon)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(DesignSystem.accentPrimary.opacity(0.85))
                                .frame(width: 14)

                            Text(task.title)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundColor(DesignSystem.textPrimary)
                                .strikethrough(isCompleted)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let meta = task.compactMetadataLine {
                            Text(meta)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(DesignSystem.textMuted)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open task details")
                .accessibilityIdentifier("task-card-\(task.id)")

                HStack(spacing: 4) {
                    if task.priority == .high || task.priority == .critical {
                        Circle()
                            .fill(Color(hex: task.priority.colorHex))
                            .frame(width: 7, height: 7)
                            .accessibilityLabel("\(task.priority.label) priority")
                    }
                    expandButton
                }
            }

            if !task.steps.isEmpty, task.progress > 0, task.progress < 1 {
                ProgressBarView(progress: task.progress)
                    .padding(.top, 8)
            }

            if isExpanded {
                Divider()
                    .overlay(DesignSystem.borderGlass)
                    .padding(.top, 10)

                expandedDetails

                actionButtons
            }
        }
        .elevatedSurface(padding: 12, cornerRadius: DesignSystem.radiusMD)
    }

    // MARK: - Focus stack

    private var focusStackCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingXL) {
            HStack(spacing: DesignSystem.spacingSM) {
                MetadataTagRow(tags: [TagChipView(task.lifeArea.rawValue.capitalized, style: .neutral)])
                Spacer(minLength: 0)
                TagChipView("\(task.estimatedMinutes) mins")
            }

            Button(action: onOpen) {
                Text(task.title)
                    .font(.dsTitle())
                    .foregroundColor(DesignSystem.textPrimary)
                    .multilineTextAlignment(.center)
                    .dsPrimaryText(lineLimit: 4)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("task-card-\(task.id)")

            if let firstStep = task.steps.first {
                VStack(alignment: .leading, spacing: DesignSystem.spacingXS) {
                    Text("MICRO-STEP 1")
                        .font(.dsCaption(weight: .bold))
                        .foregroundColor(DesignSystem.accentPrimary)
                    Text(firstStep.title)
                        .font(.dsBody(weight: .medium))
                        .foregroundColor(DesignSystem.textSecondary)
                        .dsPrimaryText(lineLimit: 3)
                }
                .padding(DesignSystem.spacingMD)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
            }

            MetadataTagRow(tags: task.metadataTags())

            HStack(spacing: DesignSystem.spacingLG) {
                if let onDefer {
                    SecondaryCapsuleButton(title: "Defer", icon: "arrow.left", tint: DesignSystem.warning, action: onDefer)
                        .frame(maxWidth: .infinity)
                }
                PrimaryCapsuleButton(title: "Done", icon: "checkmark", tint: DesignSystem.success, action: onComplete)
                    .frame(maxWidth: .infinity)
            }
        }
        .elevatedSurface(padding: DesignSystem.spacingXXL)
    }

    // MARK: - Shared pieces

    private var checkboxButton: some View {
        Button(action: isCompleted ? onMarkIncomplete : onComplete) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20, weight: .regular))
                .foregroundColor(isCompleted ? DesignSystem.success : Color.white.opacity(0.28))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCompleted ? "Mark incomplete" : "Mark complete")
        .accessibilityIdentifier("task-checkbox-\(task.id)")
    }

    private var expandButton: some View {
        Button(action: { withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { isExpanded.toggle() } }) {
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(DesignSystem.textMuted.opacity(0.7))
                .frame(width: 24, height: 24)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Collapse details" : "Expand details")
    }

    @ViewBuilder
    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            MetadataTagRow(tags: task.metadataTags())

            if !task.description.isEmpty {
                Text(task.description)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(DesignSystem.textSecondary)
                    .lineLimit(4)
            }

            if !task.steps.isEmpty {
                ForEach(task.steps) { step in
                    HStack(spacing: 8) {
                        Image(systemName: step.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 13))
                            .foregroundColor(step.isCompleted ? DesignSystem.success : DesignSystem.textMuted)

                        Text(step.title)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(step.isCompleted ? DesignSystem.textMuted : DesignSystem.textPrimary)
                            .strikethrough(step.isCompleted)
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        Text("\(step.estimatedMinutes)m")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(DesignSystem.textMuted)
                    }
                }
            }
        }
        .padding(.top, 8)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder
    private var actionButtons: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            if isCompleted {
                TaskActionButton(title: "Mark Incomplete", icon: "arrow.uturn.backward.circle", action: onMarkIncomplete)
                TaskActionButton(title: "Edit", icon: "pencil", action: onEdit)
                TaskActionButton(title: "Duplicate", icon: "plus.square.on.square", action: onDuplicate)
                TaskActionButton(title: "Delete", icon: "trash", style: .destructive, action: onDelete)
            } else {
                TaskActionButton(title: "Start", icon: "play.fill", style: .primary, action: onStart)
                TaskActionButton(title: "Edit", icon: "pencil", action: onEdit)
                if task.steps.isEmpty {
                    TaskActionButton(
                        title: isDecomposing ? "Breaking down..." : "Break Down",
                        icon: "square.split.2x2",
                        isDisabled: isDecomposing,
                        action: onDecompose
                    )
                }
                TaskActionButton(title: "Duplicate", icon: "plus.square.on.square", action: onDuplicate)
                TaskActionButton(title: "Delete", icon: "trash", style: .destructive, action: onDelete)
            }
        }
        .padding(.top, 8)
    }
}

/// Compact task row for dashboards and briefings.
struct CompactTaskRowView: View {
    let task: LifeTask
    var showsEnergy: Bool = true

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: task.lifeArea.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(DesignSystem.accentPrimary.opacity(0.85))
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(DesignSystem.textPrimary)
                    .lineLimit(1)

                if let meta = task.compactMetadataLine {
                    Text(meta)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(DesignSystem.textMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if showsEnergy {
                Text("\(task.estimatedMinutes)m")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(DesignSystem.textMuted)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct PrimaryCapsuleButton: View {
    let title: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.spacingSM) {
                Text(title)
                Image(systemName: icon)
            }
            .font(.dsBody(weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, DesignSystem.spacingXL)
            .padding(.vertical, DesignSystem.spacingMD)
            .background(Capsule(style: .continuous).fill(tint))
            .dsChipText()
        }
        .buttonStyle(.plain)
        .minTouchTarget()
    }
}

private struct SecondaryCapsuleButton: View {
    let title: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.spacingSM) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.dsBody(weight: .bold))
            .foregroundColor(tint)
            .padding(.horizontal, DesignSystem.spacingLG)
            .padding(.vertical, DesignSystem.spacingMD)
            .background(Capsule(style: .continuous).fill(tint.opacity(0.15)))
            .dsChipText()
        }
        .buttonStyle(.plain)
        .minTouchTarget()
    }
}
