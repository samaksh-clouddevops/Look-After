import SwiftUI
import LookAfterCore
import LookAfterFeatures

/// Interactive timeline block — constraint physics, haptics, and a11y mutations.
/// Business rules live in `TimelineConstraintViewModel`; this view only renders + routes intents.
struct LifeBlockView<Content: View>: View {
    let taskID: String
    let constraint: TimeConstraint
    let isEnabled: Bool
    @ObservedObject var viewModel: TimelineConstraintViewModel
    @Binding var scrollDisabled: Bool
    let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var verticalOffset: CGFloat = 0
    @State private var horizontalOffset: CGFloat = 0
    @State private var isDraggingVertically = false
    @State private var lastDragSample: (time: Date, y: CGFloat)?
    @State private var didFireRubberBand = false
    @State private var thresholdPulse = false

    private let engine = InteractionEngine.shared
    private let swipeThreshold = TimeConstraintPhysics.swipeThreshold

    init(
        taskID: String,
        constraint: TimeConstraint,
        isEnabled: Bool = true,
        viewModel: TimelineConstraintViewModel,
        scrollDisabled: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.taskID = taskID
        self.constraint = constraint
        self.isEnabled = isEnabled
        self.viewModel = viewModel
        self._scrollDisabled = scrollDisabled
        self.content = content()
    }

    var body: some View {
        content
            .offset(x: horizontalOffset, y: verticalOffset)
            .modifier(FluidDragVisualEffect(
                active: isDraggingVertically && constraint == .fluid && !reduceMotion
            ))
            // `.subviews` lets double-tap on the card reach EventTimelineCard; drag still wins on movement.
            .highPriorityGesture(dragGesture, including: .subviews)
            .sensoryFeedback(.impact(weight: .heavy), trigger: thresholdPulse)
            .accessibilityElement(children: .combine)
            .accessibilityValue(constraint.accessibilityDescription)
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

    // MARK: - Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged(handleDragChanged)
            .onEnded(handleDragEnded)
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        let dx = value.translation.width
        let dy = value.translation.height
        let dominantHorizontal = abs(dx) > abs(dy)

        if dominantHorizontal {
            // Soft horizontal preview while deciding mutation.
            horizontalOffset = dx * 0.35
            verticalOffset = 0
            if isDraggingVertically {
                endVerticalSession(commit: false)
            }
            return
        }

        if !isDraggingVertically {
            beginVerticalSession()
        }

        let velocityY = sampleVerticalVelocity(currentY: value.location.y)
        engine.dragTexture(velocity: Double(velocityY), constraint: constraint)

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
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
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

        if isDraggingVertically {
            // ~ minute snap from pt offset (48pt ≈ 15 min heuristics).
            let minutes = Int((verticalOffset / 3.2).rounded())
            endVerticalSession(commit: constraint != .anchored, offsetMinutes: minutes)
        }

        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82)) {
            horizontalOffset = 0
            verticalOffset = 0
        }
        didFireRubberBand = false
        lastDragSample = nil
    }

    private func beginVerticalSession() {
        isDraggingVertically = true
        scrollDisabled = true
        engine.prepare()
        viewModel.handle(.beginVerticalDrag(taskID: taskID))
    }

    private func endVerticalSession(commit: Bool, offsetMinutes: Int = 0) {
        isDraggingVertically = false
        scrollDisabled = false
        viewModel.handle(.endVerticalDrag)
        if commit, offsetMinutes != 0 {
            viewModel.handle(.commitVerticalOffset(taskID: taskID, offsetMinutes: offsetMinutes))
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

// MARK: - Fluid visual

/// iOS 17 visual effect: dim + slightly scale while a fluid block is dragged.
private struct FluidDragVisualEffect: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .opacity(active ? TimeConstraintPhysics.fluidDragOpacity : 1)
            .scaleEffect(active ? TimeConstraintPhysics.fluidDragScale : 1)
            .animation(active ? .interactiveSpring(response: 0.2, dampingFraction: 0.85) : .easeOut(duration: 0.2), value: active)
    }
}
