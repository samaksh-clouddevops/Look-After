import AppIntents
import SwiftUI
import WidgetKit

/// Control Center buttons for Capture and Start Focus (Phase G3).
struct LookAfterCaptureControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "LookAfterCaptureControl") {
            ControlWidgetButton(action: WidgetOpenCaptureIntent()) {
                Label("Capture", systemImage: "plus.circle.fill")
            }
        }
        .displayName("Capture")
        .description("Open Look After Capture.")
    }
}

struct LookAfterStartFocusControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "LookAfterStartFocusControl") {
            ControlWidgetButton(action: WidgetStartHeroTaskIntent()) {
                Label("Start Focus", systemImage: "play.circle.fill")
            }
        }
        .displayName("Start Focus")
        .description("Start focus on your next task.")
    }
}
