import Foundation
import LookAfterCore

public enum TodayMetricKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case capacity
    case sleep
    case recovery
    case medication
    case cycle
    case freeTime
    case weather
    case focusWindow
    case momentum

    public var id: String { rawValue }

    public var defaultIcon: String {
        switch self {
        case .capacity: return "brain.head.profile"
        case .sleep: return "moon.fill"
        case .recovery: return "heart.fill"
        case .medication: return "pills.fill"
        case .cycle: return "circle.circle.fill"
        case .freeTime: return "calendar"
        case .weather: return "cloud.sun.fill"
        case .focusWindow: return "bolt.fill"
        case .momentum: return "flame.fill"
        }
    }
}

public struct TodayExecutiveMetric: Identifiable, Sendable, Equatable {
    public var id: String { kind.rawValue }
    public var kind: TodayMetricKind
    public var icon: String
    public var value: String
    public var relevance: Double
    public var isHighlighted: Bool

    public init(
        kind: TodayMetricKind,
        icon: String? = nil,
        value: String,
        relevance: Double,
        isHighlighted: Bool = false
    ) {
        self.kind = kind
        self.icon = icon ?? kind.defaultIcon
        self.value = value
        self.relevance = relevance
        self.isHighlighted = isHighlighted
    }
}

public struct TodayWeatherMetricsInput: Sendable, Equatable {
    public var temperatureCelsius: Int?
    public var conditionLabel: String
    public var isAvailable: Bool

    public init(temperatureCelsius: Int? = nil, conditionLabel: String = "—", isAvailable: Bool = false) {
        self.temperatureCelsius = temperatureCelsius
        self.conditionLabel = conditionLabel
        self.isAvailable = isAvailable
    }

    public var isRainy: Bool {
        let lower = conditionLabel.lowercased()
        return lower.contains("rain") || lower.contains("drizzle") || lower.contains("storm")
    }
}

public struct TodayMetricsInput: Sendable {
    public var executiveCapacity: ExecutiveCapacityState
    public var sleep: BriefingSleepData
    public var healthSnapshot: BriefingHealthSnapshot
    public var calendar: BriefingCalendarData
    public var weather: TodayWeatherMetricsInput
    public var medications: [Medication]
    public var focusWindows: [BriefingFocusWindow]
    public var cycleSnapshot: CycleSnapshot
    public var completedTodayCount: Int
    public var isWeekend: Bool
    public var now: Date

    public init(
        executiveCapacity: ExecutiveCapacityState,
        sleep: BriefingSleepData = BriefingSleepData(isAvailable: false),
        healthSnapshot: BriefingHealthSnapshot = BriefingHealthSnapshot(
            readinessLabel: "—",
            readinessScore: 50,
            readinessBand: "—",
            energyPercent: 50,
            energyLevel: EnergyLevel.moderate.rawValue,
            recoveryLabel: "—",
            focusWindow: "—",
            isHealthConnected: false
        ),
        calendar: BriefingCalendarData = BriefingCalendarData(isConnected: false),
        weather: TodayWeatherMetricsInput = TodayWeatherMetricsInput(),
        medications: [Medication] = [],
        focusWindows: [BriefingFocusWindow] = [],
        cycleSnapshot: CycleSnapshot = .disabled,
        completedTodayCount: Int = 0,
        isWeekend: Bool = false,
        now: Date = Date()
    ) {
        self.executiveCapacity = executiveCapacity
        self.sleep = sleep
        self.healthSnapshot = healthSnapshot
        self.calendar = calendar
        self.weather = weather
        self.medications = medications
        self.focusWindows = focusWindows
        self.cycleSnapshot = cycleSnapshot
        self.completedTodayCount = completedTodayCount
        self.isWeekend = isWeekend
        self.now = now
    }
}

/// Selects the most relevant compact metrics for the Today strip — max five, Brain-prioritized.
public enum TodayExecutiveMetricsEngine {
    public static let maxVisible = 5

    public static func select(_ input: TodayMetricsInput) -> [TodayExecutiveMetric] {
        var candidates: [TodayExecutiveMetric] = []

        candidates.append(capacityMetric(input))
        if let sleep = sleepMetric(input) { candidates.append(sleep) }
        if let recovery = recoveryMetric(input) { candidates.append(recovery) }
        if let med = medicationMetric(input) { candidates.append(med) }
        if let cycle = cycleMetric(input) { candidates.append(cycle) }
        if let free = freeTimeMetric(input) { candidates.append(free) }
        if let weather = weatherMetric(input) { candidates.append(weather) }
        if let focus = focusWindowMetric(input) { candidates.append(focus) }
        if let momentum = momentumMetric(input) { candidates.append(momentum) }

        var selected = Array(
            candidates
                .sorted { $0.relevance > $1.relevance }
                .prefix(maxVisible)
        )

        // Capacity is always present — swap out lowest if missing.
        if !selected.contains(where: { $0.kind == .capacity }) {
            if selected.count >= maxVisible {
                selected.removeLast()
            }
            selected.insert(capacityMetric(input), at: 0)
        }

        selected.sort { $0.relevance > $1.relevance }

        if let highlightIndex = selected.indices.max(by: { selected[$0].relevance < selected[$1].relevance }) {
            for idx in selected.indices {
                selected[idx].isHighlighted = idx == highlightIndex
            }
        }

        return selected
    }

    // MARK: - Builders

    private static func capacityMetric(_ input: TodayMetricsInput) -> TodayExecutiveMetric {
        let band = input.executiveCapacity.band
        var relevance = 88.0
        switch band {
        case .peakFocus: relevance = 92
        case .goodCapacity: relevance = 86
        case .moderateCapacity: relevance = 82
        case .lowCapacity: relevance = 90
        case .recoveryMode: relevance = 94
        }
        return TodayExecutiveMetric(kind: .capacity, value: band.shortLabel, relevance: relevance)
    }

    private static func sleepMetric(_ input: TodayMetricsInput) -> TodayExecutiveMetric? {
        guard input.sleep.isAvailable || input.healthSnapshot.sleepHours != nil else { return nil }
        let value: String
        if let hours = input.sleep.totalHours {
            value = formatSleepHours(hours)
        } else if let label = input.healthSnapshot.sleepHours {
            value = label
        } else {
            return nil
        }
        var relevance = 72.0
        if input.sleep.sleepDebtHours >= 1.5 { relevance = 85 }
        if Calendar.current.component(.hour, from: input.now) < 12 { relevance += 8 }
        return TodayExecutiveMetric(kind: .sleep, value: value, relevance: relevance)
    }

    private static func recoveryMetric(_ input: TodayMetricsInput) -> TodayExecutiveMetric? {
        guard input.healthSnapshot.isHealthConnected else { return nil }
        let label = shortRecoveryLabel(input.healthSnapshot.recoveryLabel)
        var relevance = 68.0
        if input.healthSnapshot.recoveryPercent >= 75 { relevance = 78 }
        if input.healthSnapshot.recoveryPercent <= 40 { relevance = 84 }
        return TodayExecutiveMetric(kind: .recovery, value: label, relevance: relevance)
    }

    private static func medicationMetric(_ input: TodayMetricsInput) -> TodayExecutiveMetric? {
        let pending = input.medications.filter { !$0.isTaken }
        guard !pending.isEmpty else { return nil }

        let cal = Calendar.current
        let sorted = pending.sorted { $0.scheduledTime < $1.scheduledTime }
        guard let next = sorted.first else { return nil }

        let minutesUntil = Int(next.scheduledTime.timeIntervalSince(input.now) / 60)
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let timeLabel = formatter.string(from: next.scheduledTime)

        let value: String
        var relevance = 70.0
        if minutesUntil <= 0 {
            value = "Due now"
            relevance = 96
        } else if minutesUntil <= 30 {
            value = "\(minutesUntil)m"
            relevance = 93
        } else if minutesUntil <= 120 {
            value = timeLabel
            relevance = 82
        } else {
            return nil
        }

        return TodayExecutiveMetric(kind: .medication, value: value, relevance: relevance)
    }

    private static func cycleMetric(_ input: TodayMetricsInput) -> TodayExecutiveMetric? {
        guard input.cycleSnapshot.isEnabled, CycleFeatureGate.isActive else { return nil }
        let snapshot = input.cycleSnapshot
        var relevance = 68.0
        let value: String
        if let day = snapshot.cycleDay {
            value = "D\(day) \(snapshot.phase.displayLabel.prefix(4))"
        } else {
            value = snapshot.phase.displayLabel
        }

        switch snapshot.phase {
        case .menstrual:
            relevance = 92
        case .luteal:
            relevance = 78
        case .ovulation:
            relevance = 72
        case .follicular:
            relevance = 65
        case .unknown:
            relevance = 55
        }

        if let days = snapshot.daysUntilPeriod, days <= 2 {
            relevance = max(relevance, 88)
        }

        return TodayExecutiveMetric(kind: .cycle, value: value, relevance: relevance)
    }

    private static func freeTimeMetric(_ input: TodayMetricsInput) -> TodayExecutiveMetric? {
        if let minutes = input.calendar.minutesUntilStart, minutes > 0 {
            let value: String
            var relevance = 74.0
            if minutes <= 30 {
                value = "Meet \(minutes)m"
                relevance = 91
            } else if minutes <= 90 {
                value = "Meet \(minutes)m"
                relevance = 80
            } else {
                let until = Calendar.current.date(byAdding: .minute, value: minutes, to: input.now) ?? input.now
                let formatter = DateFormatter()
                formatter.dateFormat = "h:mm a"
                value = "Free til \(formatter.string(from: until))"
                relevance = 76
            }
            return TodayExecutiveMetric(kind: .freeTime, icon: "calendar", value: value, relevance: relevance)
        }

        if input.calendar.nextEventTitle == nil {
            return TodayExecutiveMetric(kind: .freeTime, icon: "calendar", value: "All clear", relevance: 62)
        }

        return nil
    }

    private static func weatherMetric(_ input: TodayMetricsInput) -> TodayExecutiveMetric? {
        guard input.weather.isAvailable else { return nil }
        let value: String
        if let temp = input.weather.temperatureCelsius {
            value = "\(temp)°"
        } else {
            value = input.weather.conditionLabel
        }

        var relevance = 55.0
        if input.weather.isRainy { relevance = 86 }
        if input.isWeekend && !input.weather.isRainy { relevance = 72 }

        let icon: String
        if input.weather.isRainy {
            icon = "cloud.rain.fill"
        } else if input.weather.conditionLabel.lowercased().contains("clear") {
            icon = "sun.max.fill"
        } else {
            icon = "cloud.sun.fill"
        }

        return TodayExecutiveMetric(kind: .weather, icon: icon, value: value, relevance: relevance)
    }

    private static func focusWindowMetric(_ input: TodayMetricsInput) -> TodayExecutiveMetric? {
        guard let window = input.focusWindows.first else {
            if input.isWeekend { return nil }
            let fallback = input.healthSnapshot.focusWindow
            guard fallback != UserFacingCopy.noFocusWindowToday, !fallback.isEmpty else { return nil }
            return TodayExecutiveMetric(kind: .focusWindow, value: shortFocusLabel(fallback), relevance: 77)
        }
        return TodayExecutiveMetric(
            kind: .focusWindow,
            value: shortFocusLabel(window.timeRange),
            relevance: 79
        )
    }

    private static func momentumMetric(_ input: TodayMetricsInput) -> TodayExecutiveMetric? {
        guard input.completedTodayCount >= 2 else { return nil }
        let value = input.completedTodayCount >= 4 ? "High" : "Building"
        let relevance = input.completedTodayCount >= 4 ? 73.0 : 66.0
        return TodayExecutiveMetric(kind: .momentum, value: value, relevance: relevance)
    }

    // MARK: - Formatting

    private static func formatSleepHours(_ hours: Double) -> String {
        let whole = Int(hours)
        let minutes = Int((hours - Double(whole)) * 60)
        if minutes > 0 { return "\(whole)h \(minutes)m" }
        return "\(whole)h"
    }

    private static func shortRecoveryLabel(_ label: String) -> String {
        let lower = label.lowercased()
        if lower.contains("excellent") || lower.contains("high") { return "Excellent" }
        if lower.contains("recovered") || lower.contains("good") { return "Recovered" }
        if lower.contains("fair") || lower.contains("moderate") { return "Fair" }
        if lower.contains("low") || lower.contains("depleted") { return "Low" }
        return label.split(separator: " ").first.map(String.init) ?? label
    }

    private static func shortFocusLabel(_ label: String) -> String {
        if label.contains("–") || label.contains("-") {
            let parts = label.components(separatedBy: CharacterSet(charactersIn: "–-"))
            if let last = parts.last?.trimmingCharacters(in: .whitespaces), !last.isEmpty {
                return last
            }
        }
        if label.lowercased().contains("min") {
            let digits = label.filter { $0.isNumber }
            if let mins = Int(digits), mins > 0 { return "\(mins)m" }
        }
        return label
    }
}
