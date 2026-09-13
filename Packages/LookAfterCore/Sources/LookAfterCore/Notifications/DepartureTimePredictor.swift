import Foundation

/// Predicts a "time to leave" for a fixed arrival commitment (e.g. work start) using
/// straight-line distance between two coordinates and an assumed average travel speed.
///
/// Deliberately avoids `MapKit`/`MKDirections` (network round-trip, harder to unit test)
/// and any paid-entitlement APIs — this is a pure-Foundation estimate good enough for a
/// soft planning nudge, not turn-by-turn navigation.
public enum DepartureTimePredictor {

    /// Average assumed travel speed in km/h. Chosen as a conservative mixed
    /// urban/suburban driving estimate; straight-line distance already undercounts
    /// real road distance, so a moderate speed keeps the estimate from being too optimistic.
    public static let defaultAverageSpeedKmh: Double = 30

    /// Extra minutes added on top of the raw travel-time estimate to account for
    /// parking, walking in, etc.
    public static let defaultBufferMinutes: Int = 10

    /// Straight-line (great-circle) road-distance multiplier — real roads are rarely
    /// a straight line, so the raw haversine distance is scaled up before converting to time.
    public static let routeDistanceMultiplier: Double = 1.3

    public struct Prediction: Equatable {
        public let departureDate: Date
        public let arrivalDate: Date
        public let travelMinutes: Int
        public let distanceKm: Double
    }

    /// Computes when the user should leave `origin` to arrive at `destination` by
    /// `arrivalHour:arrivalMinute` on `day`.
    public static func predict(
        originLatitude: Double,
        originLongitude: Double,
        destinationLatitude: Double,
        destinationLongitude: Double,
        arrivalHour: Int,
        arrivalMinute: Int,
        on day: Date,
        calendar: Calendar = .current,
        averageSpeedKmh: Double = defaultAverageSpeedKmh,
        bufferMinutes: Int = defaultBufferMinutes
    ) -> Prediction? {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = arrivalHour
        components.minute = arrivalMinute
        components.second = 0
        guard let arrivalDate = calendar.date(from: components) else { return nil }

        let straightLineKm = haversineDistanceKm(
            lat1: originLatitude, lon1: originLongitude,
            lat2: destinationLatitude, lon2: destinationLongitude
        )
        // Coincident coordinates (e.g. home == office not yet set distinctly) — nothing to predict.
        guard straightLineKm > 0.05 else { return nil }

        let estimatedRoadKm = straightLineKm * routeDistanceMultiplier
        let travelHours = estimatedRoadKm / max(averageSpeedKmh, 1)
        let travelMinutes = max(1, Int((travelHours * 60).rounded(.up))) + bufferMinutes

        let departureDate = arrivalDate.addingTimeInterval(-Double(travelMinutes) * 60)
        return Prediction(
            departureDate: departureDate,
            arrivalDate: arrivalDate,
            travelMinutes: travelMinutes,
            distanceKm: estimatedRoadKm
        )
    }

    /// Great-circle distance between two coordinates in kilometers.
    private static func haversineDistanceKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let earthRadiusKm = 6371.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let radLat1 = lat1 * .pi / 180
        let radLat2 = lat2 * .pi / 180

        let a = sin(dLat / 2) * sin(dLat / 2)
            + sin(dLon / 2) * sin(dLon / 2) * cos(radLat1) * cos(radLat2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusKm * c
    }
}
