import SwiftUI

enum HeartRateZone: Int, CaseIterable {
    case zone1 = 1
    case zone2
    case zone3
    case zone4
    case zone5

    var color: Color {
        switch self {
        case .zone1: return .blue
        case .zone2: return .green
        case .zone3: return .yellow
        case .zone4: return .orange
        case .zone5: return .red
        }
    }

    var label: String { "Z\(rawValue)" }

    static func zone(forHeartRate bpm: Double, maxHR: Int = AppSettings.maxHeartRate) -> HeartRateZone? {
        guard bpm > 0, maxHR > 0 else { return nil }
        let pct = bpm / Double(maxHR)
        switch pct {
        case ..<0.6: return .zone1
        case ..<0.7: return .zone2
        case ..<0.8: return .zone3
        case ..<0.9: return .zone4
        default: return .zone5
        }
    }
}

enum PowerZone: Int, CaseIterable {
    case zone1 = 1
    case zone2
    case zone3
    case zone4
    case zone5
    case zone6
    case zone7

    var color: Color {
        switch self {
        case .zone1: return .gray
        case .zone2: return .blue
        case .zone3: return .green
        case .zone4: return .yellow
        case .zone5: return .orange
        case .zone6: return .red
        case .zone7: return .purple
        }
    }

    var label: String { "Z\(rawValue)" }

    static func zone(forPower watts: Double, ftp: Int = AppSettings.ftp) -> PowerZone? {
        guard watts > 0, ftp > 0 else { return nil }
        let pct = watts / Double(ftp)
        switch pct {
        case ..<0.55: return .zone1
        case ..<0.75: return .zone2
        case ..<0.9: return .zone3
        case ..<1.05: return .zone4
        case ..<1.2: return .zone5
        case ..<1.5: return .zone6
        default: return .zone7
        }
    }
}
