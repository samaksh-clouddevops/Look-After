import XCTest
@testable import LifeOSData
import LifeOSCore

@MainActor
final class HealthSummaryRepositoryTests: XCTestCase {
    
    func testSavePersistsLocallyWithoutBlockingOnFirestore() async throws {
        let repo = HealthSummaryRepository()
        let userId = "test_user_health_repo"
        var summary = HealthSummary(id: "health-test-\(UUID().uuidString)", userId: userId)
        summary.totalSleepMinutes = 420
        summary.stepCount = 5_000
        summary.hrvAverage = 55
        
        let start = Date()
        try await repo.save(summary)
        let elapsed = Date().timeIntervalSince(start)
        
        XCTAssertLessThan(elapsed, 2.0, "Local-first save should return quickly, not hang on Firestore")
        
        let loaded = try await repo.getLatest(for: userId)
        XCTAssertEqual(loaded?.id, summary.id)
        XCTAssertEqual(loaded?.totalSleepMinutes, 420)
        XCTAssertEqual(loaded?.stepCount, 5_000)
    }
    
    func testGetLatestReturnsLocalWhenCloudUnavailable() async throws {
        let repo = HealthSummaryRepository()
        let userId = "offline_user_\(UUID().uuidString)"
        var summary = HealthSummary(id: "offline-\(UUID().uuidString)", userId: userId)
        summary.restingHeartRate = 62
        
        try await repo.save(summary)
        
        let latest = try await repo.getLatest(for: userId)
        XCTAssertEqual(latest?.restingHeartRate, 62)
    }
}
