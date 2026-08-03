import Foundation
import LifeOSCore

public extension PersonalAnalyticsReport {
    /// Maps cached analytics charts into Daily Briefing trend cards.
    var briefingWeeklyTrends: BriefingWeeklyTrends {
        var sleep: [BriefingTrendPoint] = []
        var energy: [BriefingTrendPoint] = []
        var steps: [BriefingTrendPoint] = []
        var tasks: [BriefingTrendPoint] = []

        for chart in charts {
            let points = chart.points.map {
                BriefingTrendPoint(id: $0.id, label: $0.label, value: $0.value)
            }
            switch chart.metric {
            case .sleep: sleep = points
            case .energy: energy = points
            case .steps: steps = points
            case .taskCompletion: tasks = points
            default: break
            }
        }

        return BriefingWeeklyTrends(
            sleep: sleep,
            energy: energy,
            steps: steps,
            taskCompletion: tasks
        )
    }
}
