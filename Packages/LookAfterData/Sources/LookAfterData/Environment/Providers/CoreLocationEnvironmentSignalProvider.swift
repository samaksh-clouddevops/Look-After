import Foundation
import LookAfterCore

#if canImport(CoreLocation)
import CoreLocation
#endif

/// Always-unavailable location provider for tests and denied-permission scenarios.
/// Default until the app layer injects a real `CoreLocationEnvironmentSignalProvider`
/// configured with the user's saved home/office coordinates.
public struct UnavailableLocationEnvironmentSignalProvider: LocationEnvironmentSignalProviderProtocol {
    public var permissionDenied: Bool

    public init(permissionDenied: Bool = false) {
        self.permissionDenied = permissionDenied
    }

    public func currentSignals() async -> LocationEnvironmentSignals {
        LocationEnvironmentSignals(locationContext: .unknown, isAvailable: false, permissionDenied: permissionDenied)
    }
}

#if canImport(CoreLocation)
/// `CoreLocation`-backed location provider (LookAfterData — not LookAfterCore).
///
/// Uses only `NSLocationWhenInUseUsageDescription` — a free, no-entitlement authorization.
/// Classifies the current one-shot location against the user's saved home/office coordinates
/// (set once via Settings) within `proximityRadiusMeters`. No background tracking, no
/// `startMonitoringVisits()` (which would require `NSLocationAlwaysAndWhenInUseUsageDescription`
/// and raises unnecessary privacy friction for a soft planning signal).
///
/// `CLLocationManager` must stay on the main actor — Core Location asserts when the manager
/// is created/used across queues (seen as `_dispatch_assert_queue_fail` after task load).
public struct CoreLocationEnvironmentSignalProvider: LocationEnvironmentSignalProviderProtocol {

    @MainActor
    private final class LocationFetcher: NSObject, CLLocationManagerDelegate {
        static let shared = LocationFetcher()

        private let manager = CLLocationManager()
        private var continuation: CheckedContinuation<CLLocation?, Never>?

        private override init() {
            super.init()
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        }

        var authorizationStatus: CLAuthorizationStatus {
            manager.authorizationStatus
        }

        func currentLocation() async -> CLLocation? {
            let status = manager.authorizationStatus
            guard status == .authorizedWhenInUse || status == .authorizedAlways else {
                if status == .notDetermined {
                    manager.requestWhenInUseAuthorization()
                }
                return nil
            }
            return await withCheckedContinuation { continuation in
                self.continuation?.resume(returning: nil)
                self.continuation = continuation
                manager.requestLocation()
            }
        }

        nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            Task { @MainActor in
                continuation?.resume(returning: locations.last)
                continuation = nil
            }
        }

        nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
            Task { @MainActor in
                continuation?.resume(returning: nil)
                continuation = nil
            }
        }
    }

    private let homeCoordinate: CLLocationCoordinate2D?
    private let officeCoordinate: CLLocationCoordinate2D?
    private let customPlaces: [SavedPlace]
    private let proximityRadiusMeters: Double

    public init(
        homeLatitude: Double?,
        homeLongitude: Double?,
        officeLatitude: Double?,
        officeLongitude: Double?,
        customPlaces: [SavedPlace] = [],
        proximityRadiusMeters: Double = 150
    ) {
        if let lat = homeLatitude, let lon = homeLongitude {
            self.homeCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        } else {
            self.homeCoordinate = nil
        }
        if let lat = officeLatitude, let lon = officeLongitude {
            self.officeCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        } else {
            self.officeCoordinate = nil
        }
        self.customPlaces = customPlaces
        self.proximityRadiusMeters = proximityRadiusMeters
    }

    public func currentSignals() async -> LocationEnvironmentSignals {
        let status = await LocationFetcher.shared.authorizationStatus
        if status == .denied || status == .restricted {
            return LocationEnvironmentSignals(locationContext: .unknown, isAvailable: false, permissionDenied: true)
        }
        guard let current = await LocationFetcher.shared.currentLocation() else {
            return .unavailable
        }
        let (context, placeName) = classify(current)
        return LocationEnvironmentSignals(locationContext: context, isAvailable: true, permissionDenied: false, customPlaceName: placeName)
    }

    private func classify(_ location: CLLocation) -> (LocationContext, String?) {
        if let home = homeCoordinate,
           location.distance(from: CLLocation(latitude: home.latitude, longitude: home.longitude)) <= proximityRadiusMeters {
            return (.home, nil)
        }
        if let office = officeCoordinate,
           location.distance(from: CLLocation(latitude: office.latitude, longitude: office.longitude)) <= proximityRadiusMeters {
            return (.office, nil)
        }
        if let nearest = customPlaces
            .map({ ($0, location.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))) })
            .filter({ $0.1 <= proximityRadiusMeters })
            .min(by: { $0.1 < $1.1 }) {
            return (.other, nearest.0.name)
        }
        return (.other, nil)
    }
}
#endif
