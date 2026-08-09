import XCTest
@testable import LookAfterHealth
import LookAfterCore

final class HealthConnectionStatusResolverTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testTrackingOffWhenHealthDisabled() {
        let input = HealthConnectionStatusInput(
            isHealthEnabled: false,
            isHealthKitAvailable: true,
            isSignedIn: true,
            now: now
        )
        let status = HealthConnectionStatusResolver.resolve(input)
        XCTAssertEqual(status.kind, .trackingOff)
        XCTAssertEqual(status.primaryAction, .openAppSettings)
    }

    func testAccessBlockedWhenAuthorizationDenied() {
        let input = HealthConnectionStatusInput(
            isHealthEnabled: true,
            isHealthKitAvailable: true,
            isSignedIn: true,
            lastSyncDate: now,
            authorizationGranted: false,
            now: now
        )
        let status = HealthConnectionStatusResolver.resolve(input)
        XCTAssertEqual(status.kind, .accessBlocked)
        XCTAssertEqual(status.primaryAction, .openHealth)
    }

    func testWaitingForDataWhenConnectedButEmpty() {
        let input = HealthConnectionStatusInput(
            isHealthEnabled: true,
            isHealthKitAvailable: true,
            isSignedIn: true,
            lastSyncDate: now,
            authorizationGranted: true,
            hasAnyImportedMetrics: false,
            now: now
        )
        let status = HealthConnectionStatusResolver.resolve(input)
        XCTAssertEqual(status.kind, .waitingForData)
        XCTAssertFalse(status.headline.contains("Link Apple Health"))
    }

    func testNotSetUpWhenNeverConnected() {
        let input = HealthConnectionStatusInput(
            isHealthEnabled: true,
            isHealthKitAvailable: true,
            isSignedIn: true,
            authorizationGranted: nil,
            now: now
        )
        let status = HealthConnectionStatusResolver.resolve(input)
        XCTAssertEqual(status.kind, .notSetUp)
        XCTAssertEqual(status.primaryAction, .connect)
    }

    func testAllGoodWhenMetricsPresent() {
        let input = HealthConnectionStatusInput(
            isHealthEnabled: true,
            isHealthKitAvailable: true,
            isSignedIn: true,
            lastSyncDate: now,
            authorizationGranted: true,
            hasSleepData: true,
            hasActivityData: true,
            hasHeartRateData: true,
            hasHRVData: true,
            hasAnyImportedMetrics: true,
            now: now
        )
        let status = HealthConnectionStatusResolver.resolve(input)
        XCTAssertEqual(status.kind, .allGood)
        XCTAssertFalse(status.needsAttention)
    }

    func testPartialDataWhenOnlyStepsPresent() {
        let input = HealthConnectionStatusInput(
            isHealthEnabled: true,
            isHealthKitAvailable: true,
            isSignedIn: true,
            lastSyncDate: now,
            authorizationGranted: true,
            hasSleepData: false,
            hasActivityData: true,
            hasHeartRateData: false,
            hasAnyImportedMetrics: true,
            now: now
        )
        let status = HealthConnectionStatusResolver.resolve(input)
        XCTAssertEqual(status.kind, .partialData)
        XCTAssertTrue(status.missingMetrics.contains("Sleep"))
    }

    func testSyncStaleWhenLastSyncOld() {
        let stale = now.addingTimeInterval(-25 * 60 * 60)
        let input = HealthConnectionStatusInput(
            isHealthEnabled: true,
            isHealthKitAvailable: true,
            isSignedIn: true,
            lastSyncDate: stale,
            authorizationGranted: true,
            hasSleepData: true,
            hasActivityData: true,
            hasAnyImportedMetrics: true,
            now: now
        )
        let status = HealthConnectionStatusResolver.resolve(input)
        XCTAssertEqual(status.kind, .syncStale)
        XCTAssertEqual(status.primaryAction, .syncNow)
    }
}
