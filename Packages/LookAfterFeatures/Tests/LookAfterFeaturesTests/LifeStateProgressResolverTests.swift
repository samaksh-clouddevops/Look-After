import XCTest
@testable import LookAfterFeatures
import LookAfterCore

final class LifeStateProgressResolverTests: XCTestCase {

    func testUsesBriefingHealthSnapshotSignals() {
        let snapshot = BriefingHealthSnapshot(
            readinessLabel: "Sharp",
            readinessScore: 82,
            readinessBand: "High",
            sleepHours: "7.2h",
            sleepQuality: "Good",
            energyPercent: 74,
            energyLevel: EnergyLevel.high.rawValue,
            recoveryLabel: "Recovered",
            recoveryPercent: 68,
            focusWindow: "9:00 AM – 12:00 PM",
            isHealthConnected: true,
            hasOvernightHealthSignal: true
        )

        let progress = LifeStateProgressResolver.resolve(healthSnapshot: snapshot)

        XCTAssertEqual(progress.energy, 0.74, accuracy: 0.001)
        XCTAssertEqual(progress.focus, 0.82, accuracy: 0.001)
        XCTAssertEqual(progress.wellbeing, 0.68, accuracy: 0.001)
    }

    func testWithoutOvernightSignalUsesEstimatedEnergyAndRecovery() {
        let snapshot = BriefingHealthSnapshot(
            readinessLabel: "Steady",
            readinessScore: 61,
            readinessBand: "Moderate",
            energyPercent: 72,
            energyLevel: EnergyLevel.moderate.rawValue,
            recoveryLabel: "Moderate",
            recoveryPercent: 55,
            focusWindow: "10:00 AM – 1:00 PM",
            isHealthConnected: true,
            hasOvernightHealthSignal: false
        )

        let progress = LifeStateProgressResolver.resolve(healthSnapshot: snapshot)

        XCTAssertEqual(progress.energy, 0.72, accuracy: 0.001)
        XCTAssertEqual(progress.focus, 0.61, accuracy: 0.001)
        XCTAssertEqual(progress.wellbeing, 0.55, accuracy: 0.001)
    }

    func testSleepFallbackForWellbeingWhenRecoveryUnavailable() {
        let snapshot = BriefingHealthSnapshot(
            readinessLabel: "Steady",
            readinessScore: 55,
            readinessBand: "Moderate",
            energyPercent: 0,
            energyLevel: EnergyLevel.moderate.rawValue,
            recoveryLabel: "No data",
            recoveryPercent: 0,
            focusWindow: "—",
            isHealthConnected: false,
            hasOvernightHealthSignal: false
        )
        let sleep = BriefingSleepData(totalHours: 6.4, isAvailable: true)

        let progress = LifeStateProgressResolver.resolve(healthSnapshot: snapshot, sleep: sleep)

        XCTAssertEqual(progress.wellbeing, 0.8, accuracy: 0.001)
    }
}
