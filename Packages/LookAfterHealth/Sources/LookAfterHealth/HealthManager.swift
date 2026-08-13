import Foundation
import HealthKit
import LookAfterCore

/// Result of probing whether HealthKit read queries can execute after authorization.
public struct HealthReadAccessStatus: Sendable, Equatable {
    public var authorizationRequested: Bool
    public var canExecuteQueries: Bool
    public var hasSampleData: Bool

    public var isAuthorizedForRead: Bool { canExecuteQueries }

    public init(authorizationRequested: Bool, canExecuteQueries: Bool, hasSampleData: Bool) {
        self.authorizationRequested = authorizationRequested
        self.canExecuteQueries = canExecuteQueries
        self.hasSampleData = hasSampleData
    }
}

/// Central HealthKit manager — reads all health data from iPhone (including Apple Watch data).
/// Apple Watch data automatically syncs to iPhone's HealthKit store, so we get Watch data for free.
@MainActor
public final class HealthManager: ObservableObject {
    
    @Published public var isAuthorized: Bool = false
    @Published public var latestSummary: HealthSummary?
    @Published public var error: String?
    
    private let healthStore = HKHealthStore()
    
    public var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }
    
    /// Per-query ceiling so HealthKit callbacks cannot block sync indefinitely.
    public var queryTimeoutSeconds: TimeInterval = 15
    
    public init() {}
    
    private enum HealthManagerError: LocalizedError {
        case queryTimeout
        
        var errorDescription: String? {
            switch self {
            case .queryTimeout:
                return "Health data request timed out"
            }
        }
    }
    
    // MARK: - Authorization
    
    /// Clears cached authorization so the next connect re-shows the Health permission flow when needed.
    public func resetAuthorizationPrompt() {
        isAuthorized = false
    }

    /// Request authorization to read health data types, then probe whether queries can execute.
    public func requestAuthorization() async throws -> Bool {
        guard isAvailable else {
            error = "HealthKit is not available on this device"
            isAuthorized = false
            return false
        }

        // Give SwiftUI time to finish presenting the connect sheet before HealthKit shows its dialog.
        try await Task.sleep(nanoseconds: 450_000_000)

        let readTypes: Set<HKObjectType> = Self.readObjectTypes

        try await healthStore.requestAuthorization(toShare: Set(), read: readTypes)
        UserDefaults.standard.set(true, forKey: "healthAuthorizationRequested")

        let access = await assessReadAccess()
        isAuthorized = access.canExecuteQueries
        if !access.canExecuteQueries {
            error = "Could not read Apple Health data. Enable Sleep, Steps, and Heart Rate in Settings → Health → \(UserFacingCopy.productName)."
        } else {
            error = nil
        }
        return access.canExecuteQueries
    }

    /// Re-probes read access without showing the authorization dialog again.
    public func verifyReadAccess() async -> Bool {
        let access = await assessReadAccess()
        isAuthorized = access.canExecuteQueries
        if !access.canExecuteQueries {
            error = "Health read access unavailable. Check Settings → Health → \(UserFacingCopy.productName)."
        }
        return access.canExecuteQueries
    }

    /// Executes lightweight HealthKit queries to verify read access — does not assume authorization from the dialog alone.
    public func assessReadAccess() async -> HealthReadAccessStatus {
        guard isAvailable else {
            return HealthReadAccessStatus(authorizationRequested: false, canExecuteQueries: false, hasSampleData: false)
        }

        let requested = UserDefaults.standard.bool(forKey: "healthAuthorizationRequested")
        // Still probe HealthKit — access may have been granted via Settings without our prompt flag.
        var canQuery = false
        var hasData = false

        do {
            let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
            let startOfDay = Calendar.current.startOfDay(for: Date())
            let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)
            if let stats = try await fetchStatistics(type: stepsType, predicate: predicate, options: .cumulativeSum) {
                canQuery = true
                let steps = Int(stats.sumQuantity()?.doubleValue(for: .count()) ?? 0)
                if steps > 0 { hasData = true }
            }
        } catch {
            canQuery = false
        }

        if !hasData {
            do {
                let sleep = try await fetchSleepData()
                canQuery = true
                if sleep.totalMinutes > 0 { hasData = true }
            } catch {
                if !canQuery { canQuery = false }
            }
        }

        if canQuery, !requested {
            UserDefaults.standard.set(true, forKey: "healthAuthorizationRequested")
        }

        // Keep probing HRV as a soft signal when steps/sleep were empty.
        if !hasData {
            do {
                if let hrv = try await fetchHRVData() {
                    canQuery = true
                    if hrv > 0 { hasData = true }
                }
            } catch {
                // Soft failure — steps/sleep already decided canQuery.
            }
        }

        return HealthReadAccessStatus(
            authorizationRequested: requested || canQuery,
            canExecuteQueries: canQuery,
            hasSampleData: hasData
        )
    }

    private static var readObjectTypes: Set<HKObjectType> {
        [
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!,
            HKObjectType.quantityType(forIdentifier: .appleStandTime)!,
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!,
            HKObjectType.categoryType(forIdentifier: .mindfulSession)!,
            HKObjectType.quantityType(forIdentifier: .dietaryWater)!,
            HKObjectType.categoryType(forIdentifier: .menstrualFlow)!,
            HKObjectType.categoryType(forIdentifier: .intermenstrualBleeding)!,
            HKObjectType.categoryType(forIdentifier: .ovulationTestResult)!,
        ]
    }

    /// Reads menstrual flow samples and maps them to cycle day logs.
    public func fetchMenstrualSamples(from start: Date, to end: Date) async throws -> [CycleDayLog] {
        guard isAvailable,
              let type = HKObjectType.categoryType(forIdentifier: .menstrualFlow) else {
            return []
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [
                NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            ]) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            healthStore.execute(query)
        }

        let calendar = Calendar.current
        return samples.compactMap { sample in
            let flow = mapMenstrualFlow(sample.value)
            guard flow != .none else { return nil }
            return CycleDayLog(
                day: calendar.startOfDay(for: sample.startDate),
                flow: flow,
                source: .healthKit
            )
        }
    }

    private func mapMenstrualFlow(_ value: Int) -> CycleFlowLevel {
        guard let flow = HKCategoryValueMenstrualFlow(rawValue: value) else { return .none }
        switch flow {
        case .unspecified: return .light
        case .light: return .light
        case .medium: return .medium
        case .heavy: return .heavy
        case .none: return .none
        @unknown default: return .spotting
        }
    }
    
    // MARK: - Fetch Today's Summary
    
    /// Fetches a comprehensive health summary for today, including Apple Watch data.
    /// Pass `progress` to fetch step-by-step with live status updates (better for visible sync UI).
    /// Performance optimized: All queries run in parallel for maximum speed.
    public func fetchTodaysSummary(progress: HealthFetchProgressHandler? = nil) async throws -> HealthSummary {
        var summary = HealthSummary(date: Date())

        // Performance optimization: Always fetch in parallel (5-10s → 1-2s improvement)
        // Progress updates are sent after parallel completion
        if let progress {
            progress(.started(.sleep))
            progress(.started(.heartRate))
            progress(.started(.hrv))
            progress(.started(.activity))
            progress(.started(.workouts))
        }

        // Parallel fetch for maximum performance
        async let sleepData = fetchSleepData()
        async let heartData = fetchHeartRateData()
        async let hrvData = fetchHRVData()
        async let activityData = fetchActivityData()
        async let workoutData = fetchWorkoutData()

        // Collect all results
        let sleepResult = try? await sleepData
        let heartResult = try? await heartData
        let hrvResult = try? await hrvData
        let activityResult = await activityData
        let workoutResult = try? await workoutData

        // Apply results to summary
        if let sleep = sleepResult {
            applySleep(sleep, to: &summary)
            if let progress {
                if sleep.totalMinutes > 0 {
                    var detail = String(format: "%.1fh sleep", sleep.totalMinutes / 60)
                    if let source = sleep.primarySourceName, !source.isEmpty {
                        detail += " · \(source)"
                    }
                    if sleep.sessionCount > 1 {
                        detail += " · \(sleep.sessionCount) sessions"
                    }
                    progress(.completed(.sleep, detail: detail))
                } else {
                    progress(.noData(.sleep, detail: "No sleep recorded last night yet"))
                }
            }
        } else if let progress {
            progress(.failed(.sleep, error: "Query failed"))
        }

        if let heart = heartResult {
            applyHeart(heart, to: &summary)
            if let progress {
                var parts: [String] = []
                if let rhr = heart.resting { parts.append("RHR \(Int(rhr)) bpm") }
                if let avg = heart.average { parts.append("avg \(Int(avg)) bpm") }
                if parts.isEmpty {
                    progress(.noData(.heartRate, detail: "No heart rate samples today"))
                } else {
                    progress(.completed(.heartRate, detail: parts.joined(separator: ", ")))
                }
            }
        } else if let progress {
            progress(.failed(.heartRate, error: "Query failed"))
        }

        if let hrv = hrvResult {
            summary.hrvAverage = hrv
            if let progress {
                progress(.completed(.hrv, detail: "\(Int(hrv)) ms"))
            }
        } else if let progress {
            if hrvResult == nil {
                progress(.noData(.hrv, detail: "No HRV reading yet today"))
            } else {
                progress(.failed(.hrv, error: "Query failed"))
            }
        }

        applyActivity(activityResult, to: &summary)
        if let progress {
            var parts: [String] = []
            if activityResult.steps > 0 { parts.append("\(activityResult.steps) steps") }
            if activityResult.calories > 0 { parts.append("\(Int(activityResult.calories)) kcal") }
            if activityResult.exerciseMinutes > 0 { parts.append("\(activityResult.exerciseMinutes) min exercise") }
            if parts.isEmpty {
                progress(.noData(.activity, detail: "No activity recorded yet today"))
            } else {
                progress(.completed(.activity, detail: parts.joined(separator: ", ")))
            }
        }

        if let workout = workoutResult {
            applyWorkouts(workout, to: &summary)
            if let progress {
                if workout.count > 0 {
                    let types = workout.types.prefix(2).joined(separator: ", ")
                    progress(.completed(.workouts, detail: "\(workout.count) workout(s): \(types)"))
                } else {
                    progress(.noData(.workouts, detail: "No workouts logged today"))
                }
            }
        } else if let progress {
            progress(.failed(.workouts, error: "Query failed"))
        }

        self.latestSummary = summary
        return summary
    }
    
    private func applySleep(_ sleep: SleepData, to summary: inout HealthSummary) {
        summary.totalSleepMinutes = sleep.totalMinutes
        summary.deepSleepMinutes = sleep.deepMinutes
        summary.remSleepMinutes = sleep.remMinutes
        summary.coreSleepMinutes = sleep.coreMinutes
        summary.awakeMinutes = sleep.awakeMinutes
        summary.sleepQualityScore = sleep.qualityScore
        summary.bedtime = sleep.bedtime
        summary.wakeTime = sleep.wakeTime
    }
    
    private func applyHeart(_ heart: HeartRateData, to summary: inout HealthSummary) {
        summary.restingHeartRate = heart.resting
        summary.averageHeartRate = heart.average
    }
    
    private func applyActivity(_ activity: ActivityData, to summary: inout HealthSummary) {
        summary.stepCount = activity.steps
        summary.activeCalories = activity.calories
        summary.exerciseMinutes = activity.exerciseMinutes
    }
    
    private func applyWorkouts(_ workout: WorkoutInfo, to summary: inout HealthSummary) {
        summary.workoutCount = workout.count
        summary.workoutTypes = workout.types
    }
    
    // MARK: - Sleep Analysis
    //
    // Sleep comes from HKCategoryTypeIdentifier.sleepAnalysis only.
    // Workouts (Motra, Apple Fitness, etc.) are fetched separately via fetchWorkoutData().
    
    private struct SleepData {
        var totalMinutes: Double = 0
        var deepMinutes: Double = 0
        var remMinutes: Double = 0
        var coreMinutes: Double = 0
        var awakeMinutes: Double = 0
        var qualityScore: Double = 0
        var bedtime: Date?
        var wakeTime: Date?
        var primarySourceName: String?
        var sessionCount: Int = 0
    }
    
    private func fetchSleepData() async throws -> SleepData {
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!

        let now = Date()
        let calendar = Calendar.current
        guard let windowStart = calendar.date(
            byAdding: .hour,
            value: -SleepNightAggregator.queryLookbackHours,
            to: now
        ) else {
            return SleepData()
        }

        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: now, options: [])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let samples: [HKCategorySample] = try await runQuery(timeout: queryTimeoutSeconds) { finish in
            HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, results, error in
                if let error {
                    finish(.failure(error))
                } else {
                    finish(.success(results as? [HKCategorySample] ?? []))
                }
            }
        }

        let inputs = samples.map { sample in
            SleepSampleInput(
                start: sample.startDate,
                end: sample.endDate,
                categoryValue: sample.value,
                sourceBundleId: sample.sourceRevision.source.bundleIdentifier,
                sourceName: sample.sourceRevision.source.name
            )
        }

        let aggregated = SleepNightAggregator.aggregate(samples: inputs, now: now, calendar: calendar)

        var data = SleepData()
        data.totalMinutes = aggregated.totalAsleepMinutes
        data.deepMinutes = aggregated.deepMinutes
        data.remMinutes = aggregated.remMinutes
        data.coreMinutes = aggregated.coreMinutes
        data.awakeMinutes = aggregated.awakeMinutes
        data.qualityScore = aggregated.qualityScore
        data.bedtime = aggregated.bedtime
        data.wakeTime = aggregated.wakeTime
        data.primarySourceName = aggregated.primarySourceName
        data.sessionCount = aggregated.sessionCount
        return data
    }
    
    // MARK: - Heart Rate
    
    private struct HeartRateData {
        var resting: Double?
        var average: Double?
    }
    
    private func fetchHeartRateData() async throws -> HeartRateData {
        var result = HeartRateData()
        
        // Resting heart rate
        let restingType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!
        if let restingSample = try await fetchLatestQuantity(type: restingType) {
            result.resting = restingSample.doubleValue(for: HKUnit(from: "count/min"))
        }
        
        // Average heart rate today
        let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)
        
        if let stats = try await fetchStatistics(type: hrType, predicate: predicate, options: .discreteAverage) {
            result.average = stats.averageQuantity()?.doubleValue(for: HKUnit(from: "count/min"))
        }
        
        return result
    }
    
    // MARK: - HRV
    
    private func fetchHRVData() async throws -> Double? {
        let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        guard let sample = try await fetchLatestQuantity(type: hrvType) else { return nil }
        return sample.doubleValue(for: HKUnit.secondUnit(with: .milli))
    }
    
    // MARK: - Activity
    
    private struct ActivityData {
        var steps: Int = 0
        var calories: Double = 0
        var exerciseMinutes: Int = 0
    }
    
    private func fetchActivityData() async -> ActivityData {
        var data = ActivityData()
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let now = Date()

        // Fetch each metric independently — one denied type must not fail steps.
        data.steps = await fetchTodayStepCount(from: startOfDay, to: now)
        data.calories = await fetchTodayCumulativeSum(
            identifier: .activeEnergyBurned,
            unit: .kilocalorie(),
            from: startOfDay,
            to: now
        )
        data.exerciseMinutes = Int(await fetchTodayCumulativeSum(
            identifier: .appleExerciseTime,
            unit: .minute(),
            from: startOfDay,
            to: now
        ).rounded())

        return data
    }

    private func fetchTodayStepCount(from start: Date, to end: Date) async -> Int {
        guard let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return 0 }

        for options: HKQueryOptions in [.strictStartDate, .strictEndDate, []] {
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: options)
            if let stats = try? await fetchStatistics(type: stepsType, predicate: predicate, options: .cumulativeSum),
               let sum = stats.sumQuantity()?.doubleValue(for: .count()), sum > 0 {
                return Int(sum.rounded())
            }
        }
        return 0
    }

    private func fetchTodayCumulativeSum(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from start: Date,
        to end: Date
    ) async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return 0 }

        for options: HKQueryOptions in [.strictStartDate, .strictEndDate, []] {
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: options)
            if let stats = try? await fetchStatistics(type: type, predicate: predicate, options: .cumulativeSum),
               let quantity = stats.sumQuantity() {
                let value = quantity.doubleValue(for: unit)
                if value > 0 { return value }
            }
        }
        return 0
    }
    
    // MARK: - Workouts
    
    private struct WorkoutInfo {
        var count: Int = 0
        var types: [String] = []
    }
    
    private func fetchWorkoutData() async throws -> WorkoutInfo {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)
        
        let workouts: [HKWorkout] = try await runQuery(timeout: queryTimeoutSeconds) { finish in
            HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, results, error in
                if let error {
                    finish(.failure(error))
                } else {
                    finish(.success(results as? [HKWorkout] ?? []))
                }
            }
        }
        
        return WorkoutInfo(
            count: workouts.count,
            types: workouts.map { $0.workoutActivityType.name }
        )
    }
    
    // MARK: - Helpers
    
    private func fetchLatestQuantity(type: HKQuantityType) async throws -> HKQuantity? {
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        let quantity: HKQuantity? = try await runQuery(timeout: queryTimeoutSeconds) { finish in
            HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, results, error in
                if let error {
                    finish(.failure(error))
                } else {
                    let sample = (results as? [HKQuantitySample])?.first
                    finish(.success(sample?.quantity))
                }
            }
        }
        return quantity
    }
    
    private func fetchStatistics(
        type: HKQuantityType,
        predicate: NSPredicate,
        options: HKStatisticsOptions
    ) async throws -> HKStatistics? {
        try await runQuery(timeout: queryTimeoutSeconds) { finish in
            HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: options
            ) { _, statistics, error in
                if let error {
                    finish(.failure(error))
                } else {
                    finish(.success(statistics))
                }
            }
        }
    }
    
    /// Runs a HealthKit query with a timeout so continuations always complete.
    private func runQuery<T>(
        timeout seconds: TimeInterval,
        _ makeQuery: @escaping (@escaping (Result<T, Error>) -> Void) -> HKQuery
    ) async throws -> T {
        let queryBox = HealthKitQueryBox()

        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { @MainActor in
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
                    var finished = false
                    let complete: (Result<T, Error>) -> Void = { result in
                        guard !finished else { return }
                        finished = true
                        continuation.resume(with: result)
                    }
                    let query = makeQuery(complete)
                    queryBox.query = query
                    self.healthStore.execute(query)
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw HealthManagerError.queryTimeout
            }
            defer {
                group.cancelAll()
                if let query = queryBox.query {
                    self.healthStore.stop(query)
                }
            }
            guard let value = try await group.next() else {
                throw HealthManagerError.queryTimeout
            }
            return value
        }
    }
}

/// Holds a running HealthKit query so it can be stopped on timeout.
private final class HealthKitQueryBox: @unchecked Sendable {
    var query: HKQuery?
}

// MARK: - HKWorkoutActivityType Name Extension

extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .walking: return "Walking"
        case .swimming: return "Swimming"
        case .yoga: return "Yoga"
        case .functionalStrengthTraining: return "Strength Training"
        case .highIntensityIntervalTraining: return "HIIT"
        case .hiking: return "Hiking"
        case .elliptical: return "Elliptical"
        case .dance: return "Dance"
        default: return "Workout"
        }
    }
}
