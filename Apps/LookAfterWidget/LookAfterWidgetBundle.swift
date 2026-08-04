import WidgetKit
import SwiftUI
import LookAfterCore

// MARK: - Bundle (V2 only — V1 kinds removed from gallery)

@main
struct LookAfterWidgetBundle: WidgetBundle {
    var body: some Widget {
        RecommendationWidget()
        TodayWidget()
        FocusWidget()
        HealthWidget()
        CaptureWidget()
        MedicationWidget()
        FocusLiveActivity()
        NowPinLiveActivity()
    }
}
