import SwiftUI
import LookAfterCore
import LookAfterFeatures

/// Interactive timeline block — long-press to lift, then drag to reschedule.
/// Business rules live in `TimelineConstraintViewModel`; this view only renders + routes intents.
struct LifeBlockView<Content: View>: View {
    let taskID: String
    let constraint: TimeConstraint
    let baselineStart: Date?
    let isEnabled: Bool
    let viewModel: TimelineConstraintViewModel
    let dragCoordinator: TimelineDragCoordinator
    @Binding var scrollDisabled: Bool
    let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var verticalOffset: CGFloat = 0
    @State private var horizontalOffset: CGFloat = 0
    @State private var isLifted = false
    @State private var lastDragSample: (time: Date, y: CGFloat)?
    @State private var lastDragTextureAt: Date?
    @State private var didFireRubberBand = false
    @State private var thresholdPulse = false
    @State private var lastSnappedMinute: Int?

    private let engine = InteractionEngine.shared
    private let swipeThreshold = TimeConstraintPhysics.swipeThreshold
    private let dragTextureInterval: TimeInterval = 0.07
    private let longPressDuration: Double = 0.25

    init(
        taskID: String,
        constraint: TimeConstraint,
        baselineStart: Date? = nil,
        isEnabled: Bool = true,
        viewModel: TimelineConstraintViewModel,
        dragCoordinator: TimelineDragCoordinator,
        scrollDisabled: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.taskID = taskID
        self.constraint = constraint
        self.baselineStart = baselineStart
        self.isEnabled = isEnabled
        self.viewModel = viewModel
        self.dragCoordinator = dragCoordinator
        self._scrollDisabled = scrollDisabled
        self.content = content()
    }

    var body: some View {
        blockContent
            .offset(x: horizontalOffset, y: verticalOffset)
            .scaleEffect(isLifted ? 1.03 : 1)
            .shadow(
                color: isLifted ? DesignSystem.shadowElevated.opacity(0.28) : .clear,
                radius: isLifted ? 16 : 0,
                y: isLifted ? 8 : 0
            )
            .zIndex(isLifted ? 2 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.82), value: isLifted)
            .background {
                if isLifted {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TimelineDragAnchorKey.self,
                            value: proxy.frame(in: .named("timelineScroll")).midY + verticalOffset
                        )
                    }
                }
            }
            .environment(\.timelineBlockIsDragging, isLifted)
            .sensoryFeedback(.impact(weight: .heavy), trigger: thresholdPulse)
            .accessibilityElement(children: .contain)
            .accessibilityValue(constraint.accessibilityDescription)
            .accessibilityHint(accessibilityHintText)
            .accessibilityAction(named: "Pick up to reschedule") {
                guard constraint.isSchedulerMovable else { return }
                pickUpForAccessibility()
            }
            .accessibilityAction(named: "Anchor Task") {
                viewModel.handle(.setConstraint(taskID: taskID, .anchored))
                thresholdPulse.toggle()
            }
            .accessibilityAction(named: "Make Flexible") {
                viewModel.handle(.setConstraint(taskID: taskID, .flexible))
                thresholdPulse.toggle()
            }
            .accessibilityAction(named: "Make Fluid") {
                viewModel.handle(.setConstraint(taskID: taskID, .fluid))
                thresholdPulse.toggle()
            }
    }

    private var accessibilityHintText: String {
        if constraint.isSchedulerMovable {
            return "Activate Pick up to reschedule, then drag up or down. New start time announces when you drop."
        }
        return "Press and hold for a rubber-band preview. This task is anchored."
    }

    @ViewBuilder
    private var blockContent: some View {
        if isEnabled {
            content.gesture(liftAndDragGesture)
        } else {
            content
        }
    }

    // MARK: - Gesture

    private var liftAndDragGesture: some Gesture {
        LongPressGesture(minimumDuration: longPressDuration)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged(handleLiftAndDragChanged)
            .onEnded(handleLiftAndDragEnded)
    }

    private func handleLiftAndDragChanged(_ value: SequenceGesture<LongPressGesture, DragGesture>.Value) {
        switch value {
        case .second(true, let drag?):
            if !isLifted {
                beginLiftSession()
            }
            applyDrag(drag)
        default:
            break
        }
    }

    private func handleLiftAndDragEnded(_ value: SequenceGesture<LongPressGesture, DragGesture>.Value) {
        switch value {
        case .second(true, let drag?):
            finishDrag(drag)
        default:
            cancelLift()
        }
    }

    private func beginLiftSession() {
        isLifted = true
        scrollDisabled = true
        engine.prepare()
        engine.constraintChanged(to: constraint)
        viewModel.handle(.beginVerticalDrag(taskID: taskID))
        let duration = viewModel.proposedDragDurationMinutes
            ?? TaskDurationPolicy.minimumMinutes
        dragCoordinator.begin(taskID: taskID, durationMinutes: duration)
    }

    private func cancelLift() {
        guard isLifted else { return }
        isLifted = false
        scrollDisabled = false
        verticalOffset = 0
        horizontalOffset = 0
        viewModel.handle(.endVerticalDrag)
        dragCoordinator.end()
        didFireRubberBand = false
        lastDragSample = nil
        lastDragTextureAt = nil
        lastSnappedMinute = nil
    }

    private func applyDrag(_ value: DragGesture.Value) {
        let dx = value.translation.width
        let dy = value.translation.height
        let velocityY = sampleVerticalVelocity(currentY: value.location.y)
        fireDragTextureIfNeeded(velocity: Double(velocityY))

        if abs(dx) > abs(dy), abs(dx) > 12 {
            horizontalOffset = dx * 0.35
            verticalOffset = 0
            return
        }

        horizontalOffset = 0

        switch constraint {
        case .anchored:
            let raw = Double(dy)
            let mapped = TimeConstraintPhysics.anchoredTranslation(rawDelta: raw)
            verticalOffset = CGFloat(mapped)
            if abs(mapped) >= TimeConstraintPhysics.anchoredMaxTranslation - 0.5, !didFireRubberBand {
                engine.rubberBandEdge()
                didFireRubberBand = true
            }
        case .flexible, .fluid:
            verticalOffset = dy
            publishDragPreview()
            fireSnapHapticIfNeeded()
        }
    }

    private func finishDrag(_ value: DragGesture.Value) {
        let dx = value.translation.width
        let dy = value.translation.height

        if abs(dx) >= swipeThreshold, abs(dx) > abs(dy) {
            if dx > 0 {
                viewModel.handle(.hardenConstraint(taskID: taskID))
            } else {
                viewModel.handle(.softenConstraint(taskID: taskID))
            }
            engine.constraintChanged(to: viewModel.constraint(for: taskID))
            thresholdPulse.toggle()
        }

        if isLifted, constraint.isSchedulerMovable {
            commitLiftedDrag()
        }

        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82)) {
            verticalOffset = 0
            horizontalOffset = 0
            isLifted = false
        }
        scrollDisabled = false
        viewModel.handle(.endVerticalDrag)
        dragCoordinator.end()
        didFireRubberBand = false
        lastDragSample = nil
        lastDragTextureAt = nil
        lastSnappedMinute = nil
    }

    private func commitLiftedDrag() {
        if let baseline = baselineStart {
            let proposed = TimelineDragTimeMapping.proposedStart(
                baseline: baseline,
                verticalOffset: verticalOffset
            )
            viewModel.handle(.commitVerticalDrag(taskID: taskID, proposedStart: proposed))
            announceScheduleCommit(proposed)
        } else {
            let minutes = TimelineDragTimeMapping.offsetMinutes(from: verticalOffset)
            if minutes != 0 {
                viewModel.handle(.commitVerticalOffset(taskID: taskID, offsetMinutes: minutes))
                let formatter = DateFormatter()
                formatter.dateFormat = "h:mm a"
                let label = minutes > 0 ? "Moved later by \(minutes) minutes" : "Moved earlier by \(-minutes) minutes"
                AccessibilityNotification.Announcement(label).post()
            }
        }
    }

    private func announceScheduleCommit(_ proposed: Date) {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        AccessibilityNotification.Announcement("Start time set to \(formatter.string(from: proposed))").post()
    }

    private func pickUpForAccessibility() {
        guard !isLifted else { return }
        beginLiftSession()
    }

    private func publishDragPreview() {
        guard let baseline = baselineStart else { return }
        let proposed = TimelineDragTimeMapping.proposedStart(
            baseline: baseline,
            verticalOffset: verticalOffset
        )
        dragCoordinator.updatePreview(proposedStart: proposed, anchorY: nil)
    }

    private func fireDragTextureIfNeeded(velocity: Double) {
        let now = Date()
        if let last = lastDragTextureAt, now.timeIntervalSince(last) < dragTextureInterval {
            return
        }
        lastDragTextureAt = now
        engine.dragTexture(velocity: velocity, constraint: constraint)
    }

    private func fireSnapHapticIfNeeded() {
        let snapped = TimelineDragTimeMapping.offsetMinutes(from: verticalOffset)
        if lastSnappedMinute != snapped {
            lastSnappedMinute = snapped
            engine.scheduleSnapBoundary()
        }
    }

    private func sampleVerticalVelocity(currentY: CGFloat) -> CGFloat {
        let now = Date()
        defer { lastDragSample = (now, currentY) }
        guard let last = lastDragSample else { return 0 }
        let dt = now.timeIntervalSince(last.time)
        guard dt > 0.001 else { return 0 }
        return CGFloat((currentY - last.y) / dt)
    }
}

/// Suppresses card tap-to-expand while a timeline block is being dragged.
private struct TimelineBlockIsDraggingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var timelineBlockIsDragging: Bool {
        get { self[TimelineBlockIsDraggingKey.self] }
        set { self[TimelineBlockIsDraggingKey.self] = newValue }
    }
}

/// Global Y anchor for the active drag — consumed by `TimelineDragTimeMeter`.
struct TimelineDragAnchorKey: PreferenceKey {
    static var defaultValue: CGFloat?
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        if let next = nextValue() {
            value = next
        }
    }
}

/// Global Y anchor for the active drag — consumed by `TimelineDragTimeMeter`.