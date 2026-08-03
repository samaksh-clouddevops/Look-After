import Foundation
import LifeOSCore

/// Estimates the user's cognitive state from available data.
/// Combines health data, time of day, task history, and self-reports
/// into a CognitiveSnapshot that drives AI recommendations.
public final class CognitiveModel: @unchecked Sendable {
    
    public init() {}
    
    /// Generate a cognitive snapshot from available data.
    public func generateSnapshot(
        healthSummary: HealthSummary?,
        recentEnergyReports: [EnergyReport],
        completedTasksToday: [LifeTask],
        profile: UserProfile
    ) -> CognitiveSnapshot {
        
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        
        // Calculate energy score
        let energyScore = calculateEnergyScore(
            health: healthSummary,
            reports: recentEnergyReports,
            hour: hour,
            profile: profile
        )
        
        // Calculate stress score
        let stressScore = calculateStressScore(health: healthSummary)
        
        // Calculate focus capacity
        let focusCapacity = calculateFocusCapacity(
            energyScore: energyScore,
            stressScore: stressScore,
            completedToday: completedTasksToday.count
        )
        
        // Calculate recovery score
        let recoveryScore = calculateRecoveryScore(health: healthSummary)
        
        // Calculate sleep debt
        let sleepDebt = calculateSleepDebt(health: healthSummary, target: profile.targetSleepHours)
        
        // Calculate available minutes
        let availableMinutes = calculateAvailableMinutes(hour: hour, profile: profile)
        
        // Map to energy level
        let energy = mapToEnergyLevel(score: energyScore)
        
        // Executive function score
        let efScore = calculateEFScore(
            energy: energyScore,
            stress: stressScore,
            focus: focusCapacity,
            recovery: recoveryScore,
            completedToday: completedTasksToday.count
        )
        
        // Recommended difficulty
        let difficulty = recommendDifficulty(energy: energy, focus: focusCapacity)
        
        return CognitiveSnapshot(
            energy: energy,
            energyScore: energyScore,
            stressScore: stressScore,
            focusCapacity: focusCapacity,
            recoveryScore: recoveryScore,
            sleepDebtHours: sleepDebt,
            availableMinutes: availableMinutes,
            contextNotes: generateContextNotes(energy: energy, health: healthSummary, hour: hour),
            executiveFunctionScore: efScore,
            recommendedTaskDifficulty: difficulty,
            timestamp: now
        )
    }
    
    // MARK: - Private Calculations
    
    private func calculateEnergyScore(
        health: HealthSummary?,
        reports: [EnergyReport],
        hour: Int,
        profile: UserProfile
    ) -> Double {
        var score = 0.5 // default
        
        // Factor 1: Sleep quality (40% weight)
        if let sleep = health?.totalSleepMinutes {
            let sleepHours = sleep / 60.0
            let sleepRatio = min(sleepHours / profile.targetSleepHours, 1.3)
            score = 0.4 * sleepRatio
        }
        
        // Factor 2: Time of day / circadian rhythm (30% weight)
        let isPeakHour = hour >= profile.peakEnergyStartHour && hour < profile.peakEnergyEndHour
        let isEarlyMorning = hour >= 6 && hour < profile.peakEnergyStartHour
        let isAfternoonDip = hour >= 13 && hour <= 15
        let isEvening = hour >= 20
        
        if isPeakHour {
            score += 0.3
        } else if isEarlyMorning {
            score += 0.2
        } else if isAfternoonDip {
            score += 0.1
        } else if isEvening {
            score += 0.05
        } else {
            score += 0.15
        }
        
        // Factor 3: Self-reported energy (30% weight)
        if let latestReport = reports.sorted(by: { $0.timestamp > $1.timestamp }).first {
            score += 0.3 * latestReport.energy.numericValue
        } else {
            score += 0.15 // no report, assume moderate
        }
        
        // Factor 4: HRV bonus/penalty
        if let hrv = health?.hrvAverage {
            if hrv > 60 { score += 0.05 }      // good recovery
            else if hrv < 25 { score -= 0.1 }   // high stress/fatigue
        }
        
        return max(0, min(1, score))
    }
    
    private func calculateStressScore(health: HealthSummary?) -> Double {
        guard let health = health else { return 0.3 }
        
        var stress = 0.3 // baseline
        
        if let hrv = health.hrvAverage {
            // Low HRV = high stress
            if hrv < 20 { stress = 0.9 }
            else if hrv < 30 { stress = 0.7 }
            else if hrv < 50 { stress = 0.4 }
            else { stress = 0.2 }
        }
        
        if let rhr = health.restingHeartRate {
            // Elevated resting HR can indicate stress
            if rhr > 80 { stress += 0.1 }
            else if rhr > 90 { stress += 0.2 }
        }
        
        return max(0, min(1, stress))
    }
    
    private func calculateFocusCapacity(energyScore: Double, stressScore: Double, completedToday: Int) -> Double {
        var focus = energyScore * 0.6 + (1 - stressScore) * 0.4
        
        // Task fatigue — focus decreases with more completed tasks
        let fatigueFactor = max(0, 1 - Double(completedToday) * 0.05)
        focus *= fatigueFactor
        
        return max(0, min(1, focus))
    }
    
    private func calculateRecoveryScore(health: HealthSummary?) -> Double {
        guard let health = health else { return 0.5 }
        
        var recovery = 0.5
        
        if let sleep = health.totalSleepMinutes, sleep > 420 { // > 7 hours
            recovery += 0.2
        }
        if let deep = health.deepSleepMinutes, deep > 60 { // > 1 hour deep
            recovery += 0.15
        }
        if let hrv = health.hrvAverage, hrv > 50 {
            recovery += 0.15
        }
        
        return max(0, min(1, recovery))
    }
    
    private func calculateSleepDebt(health: HealthSummary?, target: Double) -> Double {
        guard let sleep = health?.totalSleepMinutes else { return 0 }
        let sleepHours = sleep / 60.0
        return max(0, target - sleepHours)
    }
    
    private func calculateAvailableMinutes(hour: Int, profile: UserProfile) -> Int {
        let endHour = profile.workEndHour
        if hour >= endHour { return 0 }
        let startHour = max(hour, profile.workStartHour)
        return max(0, endHour - startHour) * 60
    }
    
    private func mapToEnergyLevel(score: Double) -> EnergyLevel {
        switch score {
        case 0.8...1.0: return .peak
        case 0.6..<0.8: return .high
        case 0.4..<0.6: return .moderate
        case 0.2..<0.4: return .low
        default: return .recovery
        }
    }
    
    private func calculateEFScore(
        energy: Double,
        stress: Double,
        focus: Double,
        recovery: Double,
        completedToday: Int
    ) -> Int {
        let base = (energy * 0.3 + (1 - stress) * 0.2 + focus * 0.3 + recovery * 0.2)
        let completionBonus = min(Double(completedToday) * 0.02, 0.2)
        return Int((base + completionBonus) * 100)
    }
    
    private func recommendDifficulty(energy: EnergyLevel, focus: Double) -> TaskDifficulty {
        switch energy {
        case .peak: return focus > 0.7 ? .intense : .hard
        case .high: return .hard
        case .moderate: return .medium
        case .low: return .easy
        case .recovery: return .trivial
        }
    }
    
    private func generateContextNotes(energy: EnergyLevel, health: HealthSummary?, hour: Int) -> String {
        var notes: [String] = []
        
        notes.append("Energy: \(energy.description)")
        
        if let sleep = health?.totalSleepMinutes {
            let hours = sleep / 60.0
            if hours < 6 {
                notes.append("⚠️ Poor sleep — take it easy today")
            }
        }
        
        if let hrv = health?.hrvAverage, hrv < 30 {
            notes.append("⚠️ High stress detected — consider lighter tasks")
        }
        
        if hour >= 13 && hour <= 15 {
            notes.append("🕐 Afternoon dip — normal to feel sluggish")
        }
        
        if hour >= 21 {
            notes.append("🌙 Evening — wind down, avoid starting new complex tasks")
        }
        
        return notes.joined(separator: "\n")
    }
}
