import Foundation
import HealthKit

/// Observes HealthKit sample-type updates and posts a notification so the app can sync in the background.
@MainActor
public final class HealthKitObserverService {
    public static let shared = HealthKitObserverService()

    private let healthStore = HKHealthStore()
    private var activeQueries: [HKQuery] = []
    private var isObserving = false

    private init() {}

    public func startObserving() {
        guard HKHealthStore.isHealthDataAvailable(), !isObserving else { return }
        isObserving = true

        var sampleTypes: [HKSampleType] = [HKObjectType.workoutType()]
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { sampleTypes.append(sleep) }
        for id: HKQuantityTypeIdentifier in [.stepCount, .heartRate, .heartRateVariabilitySDNN, .restingHeartRate] {
            if let type = HKQuantityType.quantityType(forIdentifier: id) { sampleTypes.append(type) }
        }

        for sampleType in sampleTypes {
            healthStore.enableBackgroundDelivery(for: sampleType, frequency: .hourly) { _, _ in }

            let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { _, completionHandler, _ in
                defer { completionHandler() }
                Task { @MainActor in
                    NotificationCenter.default.post(name: .healthKitDataDidChange, object: nil)
                }
            }
            healthStore.execute(query)
            activeQueries.append(query)
        }
    }

    public func stopObserving() {
        for query in activeQueries {
            healthStore.stop(query)
        }
        activeQueries.removeAll()
        isObserving = false
    }
}

public extension Notification.Name {
    static let healthKitDataDidChange = Notification.Name("LookAfterHealthKitDataDidChange")
}
