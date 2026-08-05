import Foundation

/// Known HealthKit writer apps — keeps sleep and workout pipelines separate.
///
/// Sleep totals come **only** from `HKCategoryTypeIdentifier.sleepAnalysis` samples
/// processed by `SleepNightAggregator`. Workout apps like Motra write `HKWorkout`
/// samples via `HealthManager.fetchWorkoutData()` and never affect sleep duration.
enum HealthSourceCatalog {
    /// Bundle IDs for apps that log workouts only (defensive filter on sleep queries).
    static let workoutOnlyBundleIds: Set<String> = [
        "com.trainfitness.ios", // Motra (formerly Train Fitness)
    ]

    static func isWorkoutOnlySource(_ bundleId: String) -> Bool {
        workoutOnlyBundleIds.contains(bundleId)
    }
}
