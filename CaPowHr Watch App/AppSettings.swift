import Foundation
import WidgetKit

enum DistanceUnit: String, CaseIterable, Identifiable {
    case miles
    case kilometers

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .miles: return "Miles"
        case .kilometers: return "Kilometers"
        }
    }

    var shortLabel: String {
        switch self {
        case .miles: return "mi"
        case .kilometers: return "km"
        }
    }
}

enum WorkoutSaveMode: String, CaseIterable, Identifiable {
    case askEveryTime
    case autoSave

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .askEveryTime: return "Ask Every Time"
        case .autoSave: return "Auto-save to Health"
        }
    }
}

enum AppSettings {
    /// App Group shared with the complications extension (a separate process with
    /// its own UserDefaults domain — anything the complication needs must go here).
    static let appGroupIdentifier = "group.com.MulcahyHeavyIndustries.CaPowHr"
    static let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier)

    static let heartRateSourceKey = "heartRateSource"
    static let distanceUnitKey = "distanceUnit"
    static let workoutSaveModeKey = "workoutSaveMode"
    static let stravaSyncEnabledKey = "stravaSyncEnabled"
    static let lastWorkoutTypeKey = "lastWorkoutType"
    static let maxHeartRateKey = "maxHeartRate"
    static let ftpKey = "ftp"
    static let structuredWorkoutTemplateKey = "structuredWorkoutTemplate"
    static let fitExportEnabledKey = "fitExportEnabled"

    static var distanceUnit: DistanceUnit {
        get {
            let raw = UserDefaults.standard.string(forKey: distanceUnitKey) ?? DistanceUnit.miles.rawValue
            return DistanceUnit(rawValue: raw) ?? .miles
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: distanceUnitKey)
        }
    }

    static var workoutSaveMode: WorkoutSaveMode {
        get {
            let raw = UserDefaults.standard.string(forKey: workoutSaveModeKey) ?? WorkoutSaveMode.askEveryTime.rawValue
            return WorkoutSaveMode(rawValue: raw) ?? .askEveryTime
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: workoutSaveModeKey)
        }
    }

    static var lastWorkoutType: WorkoutType {
        get {
            let raw = UserDefaults.standard.string(forKey: lastWorkoutTypeKey) ?? WorkoutType.indoorCycle.rawValue
            return WorkoutType(rawValue: raw) ?? .indoorCycle
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: lastWorkoutTypeKey)
            // Mirror into the App Group and refresh the complication so its
            // quick-start button tracks the last workout type.
            sharedDefaults?.set(newValue.rawValue, forKey: lastWorkoutTypeKey)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    static var maxHeartRate: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: maxHeartRateKey)
            return value > 0 ? value : 190
        }
        set {
            UserDefaults.standard.set(newValue, forKey: maxHeartRateKey)
        }
    }

    static var ftp: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: ftpKey)
            return value > 0 ? value : 200
        }
        set {
            UserDefaults.standard.set(newValue, forKey: ftpKey)
        }
    }
}

extension WorkoutType {
    var rawValue: String {
        switch self {
        case .indoorCycle: return "indoorCycle"
        case .indoorRun: return "indoorRun"
        case .indoorWalk: return "indoorWalk"
        case .indoorRow: return "indoorRow"
        }
    }

    init?(rawValue: String) {
        switch rawValue {
        case "indoorCycle": self = .indoorCycle
        case "indoorRun": self = .indoorRun
        case "indoorWalk": self = .indoorWalk
        case "indoorRow": self = .indoorRow
        default: return nil
        }
    }

    var displayName: String {
        switch self {
        case .indoorCycle: return "Ride"
        case .indoorRun: return "Run"
        case .indoorWalk: return "Walk"
        case .indoorRow: return "Row"
        }
    }

    var startButtonTitle: String {
        switch self {
        case .indoorCycle: return "Start Ride"
        case .indoorRun: return "Start Run"
        case .indoorWalk: return "Start Walk"
        case .indoorRow: return "Start Row"
        }
    }
}
