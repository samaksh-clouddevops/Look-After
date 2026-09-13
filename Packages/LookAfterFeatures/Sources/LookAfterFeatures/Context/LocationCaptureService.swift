import Foundation
import CoreLocation
import LookAfterCore

public enum LocationCaptureError: Error {
    case accessDenied
    case unavailable
}

/// One-shot current-location capture for saving "Home"/"Office" coordinates in Settings.
/// Uses only `NSLocationWhenInUseUsageDescription` — no paid entitlement required.
@MainActor
public final class LocationCaptureService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D, Error>?

    public override init() {
        super.init()
        manager.delegate = self
    }

    /// Requests "when in use" authorization if needed, then resolves the current coordinate.
    public func currentCoordinate() async throws -> CLLocationCoordinate2D {
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted {
            throw LocationCaptureError.accessDenied
        }
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last?.coordinate
        Task { @MainActor in
            guard let coordinate else {
                continuation?.resume(throwing: LocationCaptureError.unavailable)
                continuation = nil
                return
            }
            continuation?.resume(returning: coordinate)
            continuation = nil
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
