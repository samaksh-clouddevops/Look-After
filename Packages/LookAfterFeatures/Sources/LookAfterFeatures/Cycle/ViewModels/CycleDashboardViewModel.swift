import Foundation
import LookAfterCore
import LookAfterData

@MainActor
public final class CycleDashboardViewModel: ObservableObject {
    @Published public private(set) var preferences: CycleTrackingPreferences = CyclePreferencesStore.load()
    @Published public private(set) var snapshot: CycleSnapshot = .disabled
    @Published public private(set) var logs: [CycleDayLog] = []
    @Published public private(set) var insights: [CycleInsight] = []
    @Published public private(set) var periodHighlightDays: Set<Date> = []
    @Published public private(set) var predictedPeriodDays: Set<Date> = []

    private let calendar = Calendar.current

    public init() {
        refresh()
    }

    public func refresh(sleepHours: Double? = nil, hrv: Int? = nil) {
        preferences = CyclePreferencesStore.load()
        logs = CycleLogStore.load()
        snapshot = CycleEngine.snapshot(CycleEngine.Input(preferences: preferences, logs: logs))

        insights = CycleInsightBuilder.build(
            snapshot: snapshot,
            logs: logs,
            sleepHours: sleepHours,
            hrv: hrv,
            calendar: calendar
        )

        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -60, to: today) else { return }
        periodHighlightDays = CycleEngine.periodDays(in: start...today, input: CycleEngine.Input(preferences: preferences, logs: logs))

        if let predicted = snapshot.predictedPeriodStart,
           let predictedEnd = calendar.date(byAdding: .day, value: snapshot.averagePeriodLengthDays - 1, to: predicted) {
            var days = Set<Date>()
            var cursor = calendar.startOfDay(for: predicted)
            let endDay = calendar.startOfDay(for: predictedEnd)
            while cursor <= endDay {
                days.insert(cursor)
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
            predictedPeriodDays = days
        } else {
            predictedPeriodDays = []
        }
    }

    public func updatePreferences(_ preferences: CycleTrackingPreferences) {
        CyclePreferencesStore.save(preferences)
        refresh()
    }

    public func saveLog(_ log: CycleDayLog) {
        CycleLogRepository.upsert(log)
        if CycleEngine.shouldTreatFlowAsNewPeriodStart(
            log: log,
            logs: logs,
            preferences: preferences,
            calendar: calendar
        ) {
            var prefs = CyclePreferencesStore.load()
            prefs.lastPeriodStart = calendar.startOfDay(for: log.day)
            CyclePreferencesStore.save(prefs)
        }
        refresh()
    }

    public func symptomFrequency(for phase: CyclePhase) -> [(String, Int)] {
        let map = CycleEngine.symptomFrequencyByPhase(
            input: CycleEngine.Input(preferences: preferences, logs: logs)
        )[phase] ?? [:]
        return map.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }
}
