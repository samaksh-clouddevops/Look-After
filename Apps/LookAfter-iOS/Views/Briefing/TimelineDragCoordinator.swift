import Foundation
import Observation

/// Drag-only timeline state — isolated from `TimelineConstraintViewModel` so non-dragging rows
/// do not re-render on every preview tick.
@MainActor
@Observable
final class TimelineDragCoordinator {
    private(set) var activeTaskID: String?
    private(set) var proposedStart: Date?
    private(set) var durationMinutes: Int?
    private(set) var anchorY: CGFloat?

    var isDragging: Bool { activeTaskID != nil }

    func begin(taskID: String, durationMinutes: Int) {
        activeTaskID = taskID
        self.durationMinutes = durationMinutes
        proposedStart = nil
        anchorY = nil
    }

    func updatePreview(proposedStart: Date?, anchorY: CGFloat?) {
        self.proposedStart = proposedStart
        self.anchorY = anchorY
    }

    func updateAnchorY(_ anchorY: CGFloat?) {
        self.anchorY = anchorY
    }

    func end() {
        activeTaskID = nil
        proposedStart = nil
        durationMinutes = nil
        anchorY = nil
    }
}
