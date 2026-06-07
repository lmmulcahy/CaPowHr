import Foundation

enum BikeMetric: String, CaseIterable, Identifiable, Codable {
    case heartRate
    case power
    case cadence
    case distance
    case speed
    case calories

    var id: String { rawValue }

    var title: String {
        switch self {
        case .heartRate: return "HR"
        case .power: return "Power"
        case .cadence: return "Cadence"
        case .distance: return "Distance"
        case .speed: return "Speed"
        case .calories: return "Calories"
        }
    }

    var icon: String {
        switch self {
        case .heartRate: return "heart.fill"
        case .power: return "bolt.fill"
        case .cadence: return "speedometer"
        case .distance: return "map"
        case .speed: return "gauge.with.needle"
        case .calories: return "flame.fill"
        }
    }

    var colorName: String {
        switch self {
        case .heartRate: return "red"
        case .power: return "orange"
        case .cadence: return "blue"
        case .distance: return "green"
        case .speed: return "cyan"
        case .calories: return "pink"
        }
    }
}

enum TreadmillMetric: String, CaseIterable, Identifiable, Codable {
    case heartRate
    case speed
    case incline
    case distance
    case calories

    var id: String { rawValue }

    var title: String {
        switch self {
        case .heartRate: return "HR"
        case .speed: return "Speed"
        case .incline: return "Incline"
        case .distance: return "Distance"
        case .calories: return "Calories"
        }
    }

    var icon: String {
        switch self {
        case .heartRate: return "heart.fill"
        case .speed: return "figure.run"
        case .incline: return "arrow.up.right"
        case .distance: return "map"
        case .calories: return "flame.fill"
        }
    }
}

enum RowerMetric: String, CaseIterable, Identifiable, Codable {
    case pace
    case strokeRate
    case power
    case distance
    case heartRate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pace: return "Pace"
        case .strokeRate: return "SPM"
        case .power: return "Power"
        case .distance: return "Distance"
        case .heartRate: return "HR"
        }
    }
}

enum WorkoutMetricsLayout {
    private static let bikeKey = "bikeMetricsLayout"
    private static let treadmillKey = "treadmillMetricsLayout"
    private static let rowerKey = "rowerMetricsLayout"

    static func bikeMetrics() -> [BikeMetric] {
        load(key: bikeKey, default: [.heartRate, .power, .cadence, .distance])
    }

    static func saveBikeMetrics(_ metrics: [BikeMetric]) {
        save(key: bikeKey, metrics: metrics.map(\.rawValue))
    }

    static func treadmillMetrics() -> [TreadmillMetric] {
        load(key: treadmillKey, default: [.heartRate, .speed, .incline, .distance])
    }

    static func saveTreadmillMetrics(_ metrics: [TreadmillMetric]) {
        save(key: treadmillKey, metrics: metrics.map(\.rawValue))
    }

    static func rowerMetrics() -> [RowerMetric] {
        load(key: rowerKey, default: [.pace, .strokeRate, .power, .distance])
    }

    static func saveRowerMetrics(_ metrics: [RowerMetric]) {
        save(key: rowerKey, metrics: metrics.map(\.rawValue))
    }

    private static func load<T: RawRepresentable>(key: String, default defaultValue: [T]) -> [T] where T.RawValue == String {
        guard let rawValues = UserDefaults.standard.stringArray(forKey: key) else { return defaultValue }
        let mapped = rawValues.compactMap(T.init(rawValue:))
        return mapped.count == 4 ? mapped : defaultValue
    }

    private static func save(key: String, metrics: [String]) {
        UserDefaults.standard.set(Array(metrics.prefix(4)), forKey: key)
    }
}
