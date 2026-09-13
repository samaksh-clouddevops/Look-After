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
public struct CoreLocationEnvironmentSignalProvider: LocationEnvironmentSignalProviderProtocol {

    private final class LocationFetcher: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
        private let manager = CLLocationManager()
        private var continuation: CheckedContinuation<CLLocation?, Never>?

        override init() {
            super.init()
            manager.delegate = self
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
                self.continuation = continuation
                manager.requestLocation()
            }
        }

        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            continuation?.resume(returning: locations.last)
            continuation = nil
        }

        func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
            continuation?.resume(returning: nil)
            continuation = nil
        }
    }

    private let fetcher = LocationFetcher()
    private let homeCoordinate: CLLocationCoordinate2D?
    private let officeCoordinate: CLLocationCoordinate2D?
    private let proximityRadiusMeters: Double

    public init(
        homeLatitude: Double?,
        homeLongitude: Double?,
        officeLatitude: Double?,
        officeLongitude: Double?,
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
        self.proximityRadiusMeters = proximityRadiusMeters
    }

    public func currentSignals() async -> LocationEnvironmentSignals {
        let status = CLLocationManager().authorizationStatus
        if status == .denied || status == .restricted {
            return LocationEnvironmentSignals(locationContext: .unknown, isAvailable: false, permissionDenied: true)
        }
        guard let current = await fetcher.currentLocation() else {
            return .unavailable
        }
        let context = classify(current)
        return LocationEnvironmentSignals(locationContext: context, isAvailable: true, permissionDenied: false)
    }

    private func classify(_ location: CLLocation) -> LocationContext {
        if let home = homeCoordinate,
           location.distance(from: CLLocation(latitude: home.latitude, longitude: home.longitude)) <= proximityRadiusMeters {
            return .home
        }
        if let office = officeCoordinate,
           location.distance(from: CLLocation(latitude: office.latitude, longitude: office.longitude)) <= proximityRadiusMeters {
            return .office
        }
        return .other
    }
}
#endif
