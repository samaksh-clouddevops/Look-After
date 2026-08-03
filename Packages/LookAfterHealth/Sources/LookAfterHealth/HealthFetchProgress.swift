import Foundation

/// A single HealthKit data category fetched during sync.
public enum HealthFetchStep: String, CaseIterable, Sendable, Identifiable {
    case sleep
    case heartRate
    case hrv
    case activity
    case workouts
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .sleep: return "Sleep"
        case .heartRate: return "Heart Rate"
        case .hrv: return "HRV (Recovery)"
        case .activity: return "Activity"
        case .workouts: return "Workouts"
        }
    }
    
    public var explanation: String {
        switch self {
        case .sleep:
            return "Reading last night's sleep from Apple Health (includes Apple Watch)"
        case .heartRate:
            return "Reading resting and average heart rate"
        case .hrv:
            return "Reading heart rate variability — a recovery & stress signal"
        case .activity:
            return "Reading steps, active calories, and exercise minutes"
        case .workouts:
            return "Reading workouts logged today"
        }
    }
    
    public var icon: String {
        switch self {
        case .sleep: return "bed.double.fill"
        case .heartRate: return "heart.fill"
        case .hrv: return "waveform.path.ecg"
        case .activity: return "figure.walk"
        case .workouts: return "figure.run"
        }
    }
}

/// Progress events emitted while fetching HealthKit data.
public enum HealthFetchEvent: Sendable {
    case started(HealthFetchStep)
    case completed(HealthFetchStep, detail: String?)
    case noData(HealthFetchStep, detail: String?)
    case failed(HealthFetchStep, error: String)
}

public typealias HealthFetchProgressHandler = @MainActor (HealthFetchEvent) -> Void
