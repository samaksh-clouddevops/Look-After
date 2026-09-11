import CoreLocation
import Foundation

/// Fetches local weather for Today status chips via Open-Meteo (no WeatherKit entitlement required).
@MainActor
final class WeatherDisplayService: NSObject, ObservableObject {
    struct Snapshot: Equatable, Sendable {
        var conditionLabel: String
        var temperatureCelsius: Int?
        var isAvailable: Bool

        static let unavailable = Snapshot(conditionLabel: "—", temperatureCelsius: nil, isAvailable: false)

        var chipSecondary: String {
            guard isAvailable else { return "—" }
            if let temp = temperatureCelsius {
                return "\(conditionLabel), \(temp)°C"
            }
            return conditionLabel
        }
    }

    @Published private(set) var snapshot: Snapshot = .unavailable

    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var isRefreshing = false

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // Use authorizationStatus only — locationServicesEnabled() blocks the main thread.
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
            return
        }
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }

        do {
            let location = try await requestLocation()
            snapshot = try await fetchOpenMeteoWeather(for: location)
        } catch {
            // Keep last snapshot; unavailable stays as placeholder.
        }
    }

    private func requestLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            locationContinuation?.resume(throwing: CLError(.locationUnknown))
            locationContinuation = continuation
            locationManager.requestLocation()
        }
    }

    private func fetchOpenMeteoWeather(for location: CLLocation) async throws -> Snapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(location.coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        let temp = Int(decoded.current.temperature2m.rounded())
        let label = Self.conditionLabel(for: decoded.current.weatherCode)
        return Snapshot(conditionLabel: label, temperatureCelsius: temp, isAvailable: true)
    }

    /// WMO weather interpretation codes used by Open-Meteo.
    private static func conditionLabel(for code: Int) -> String {
        switch code {
        case 0:
            return "Clear"
        case 1, 2:
            return "Partly cloudy"
        case 3:
            return "Cloudy"
        case 45, 48:
            return "Foggy"
        case 51, 53, 55, 56, 57:
            return "Drizzle"
        case 61, 63, 65, 66, 67, 80, 81, 82:
            return "Rain"
        case 71, 73, 75, 77, 85, 86:
            return "Snow"
        case 95, 96, 99:
            return "Storm"
        default:
            return "Clear"
        }
    }
}

extension WeatherDisplayService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                await refresh()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        Task { @MainActor in
            locationContinuation?.resume(returning: location)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationContinuation?.resume(throwing: error)
            locationContinuation = nil
        }
    }
}

private struct OpenMeteoResponse: Decodable {
    struct Current: Decodable {
        let temperature2m: Double
        let weatherCode: Int

        enum CodingKeys: String, CodingKey {
            case temperature2m = "temperature_2m"
            case weatherCode = "weather_code"
        }
    }

    let current: Current
}
