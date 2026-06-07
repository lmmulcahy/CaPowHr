import Foundation

enum DistanceFormatter {
    static func formatDistance(_ meters: Double, unit: DistanceUnit = AppSettings.distanceUnit, decimals: Int = 1) -> (value: String, unit: String) {
        switch unit {
        case .miles:
            let miles = meters / 1609.34
            return (String(format: "%.\(decimals)f", miles), "mi")
        case .kilometers:
            let km = meters / 1000.0
            return (String(format: "%.\(decimals)f", km), "km")
        }
    }

    static func formatSpeedMps(_ mps: Double, unit: DistanceUnit = AppSettings.distanceUnit) -> (value: String, unit: String) {
        switch unit {
        case .miles:
            let mph = mps * 2.23694
            return (String(format: "%.1f", mph), "mph")
        case .kilometers:
            let kph = mps * 3.6
            return (String(format: "%.1f", kph), "km/h")
        }
    }
}
