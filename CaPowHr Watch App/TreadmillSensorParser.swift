//
//  TreadmillSensorParser.swift
//  CaPowHr Watch App
//
//  Parsing utilities for treadmill-specific BLE profiles:
//  - FTMS Treadmill Data (0x2ACD)
//

import Foundation

// MARK: - TreadmillData

/// Parsed FTMS "Treadmill Data" (0x2ACD) fields.
/// All fields are optional to allow safe parsing of truncated or partial packets.
struct TreadmillData {
    // Mandatory (per spec), but optional here to allow safe parsing of truncated packets.
    var flags: UInt16?
    var instantaneousSpeedKph: Double?

    // Optional fields (presence controlled by Flags bit indices 1-13)
    var averageSpeedKph: Double?
    var totalDistanceMeters: Double?
    var inclinePercent: Double?       // 0.1% resolution, signed
    var rampAngleDegrees: Double?     // 0.1° resolution, signed
    var positiveElevationGainMeters: Double?
    var negativeElevationGainMeters: Double?
    var instantaneousPaceSecondsPerKm: Double?  // seconds per km
    var averagePaceSecondsPerKm: Double?        // seconds per km

    // Expended Energy (bit 8)
    var totalEnergyKcal: UInt16?
    var energyPerHourKcal: UInt16?
    var energyPerMinuteKcal: UInt8?

    // Remaining optionals
    var heartRateBpm: UInt8?
    var metabolicEquivalent: Double? // 0.1 MET units
    var elapsedTimeSeconds: UInt16?
    var remainingTimeSeconds: UInt16?
    var forceOnBeltNewtons: Double?
    var powerOutputWatts: Double?

    /// Convenience conversion (derived from `instantaneousSpeedKph`).
    var instantaneousSpeedMps: Double? {
        guard let kph = instantaneousSpeedKph else { return nil }
        return kph / 3.6
    }
    /// Convenience conversion (derived from `averageSpeedKph`).
    var averageSpeedMps: Double? {
        guard let kph = averageSpeedKph else { return nil }
        return kph / 3.6
    }
    /// Convenience: pace in min/km (derived from instantaneousPaceSecondsPerKm).
    var instantaneousPaceMinPerKm: Double? {
        guard let sec = instantaneousPaceSecondsPerKm else { return nil }
        return sec / 60.0
    }
    /// Convenience: pace in min/mi (derived from instantaneousPaceSecondsPerKm).
    var instantaneousPaceMinPerMi: Double? {
        guard let secPerKm = instantaneousPaceSecondsPerKm else { return nil }
        return (secPerKm * 1.60934) / 60.0
    }
}

// MARK: - TreadmillSensorParser

/// Parsing utilities for treadmill BLE profiles.
enum TreadmillSensorParser {
    
    /// Parse FTMS Treadmill Data (0x2ACD) and return selected fields.
    static func parseTreadmillData(_ data: Data) -> TreadmillData {
        var reader = BLEDataReader(data)
        var out = TreadmillData()

        // 1) FLAGS (mandatory)
        guard let flags = reader.readUInt16LE() else { return out }
        out.flags = flags

        // Helper: check bit index in flags
        func has(_ bitIndex: Int) -> Bool {
            (flags & (1 << bitIndex)) != 0
        }

        // 2) INSTANTANEOUS SPEED: UInt16, 0.01 km/h.
        // Bit 0 is "More Data" with negated presence logic (FTMS v1.0 §4.13.1):
        // speed is present only when bit 0 is 0. Machines that split a full update
        // across several notifications set bit 0 on the continuation packets.
        if !has(0) {
            guard let speedRaw = reader.readUInt16LE() else { return out }
            out.instantaneousSpeedKph = Double(speedRaw) / 100.0
        }

        // 3) OPTIONAL FIELDS in spec order, bits 1 through 13

        // Bit 1: Average Speed (UInt16, 0.01 km/h)
        if has(1), let raw = reader.readUInt16LE() {
            out.averageSpeedKph = Double(raw) / 100.0
        } else if has(1) { return out }

        // Bit 2: Total Distance (UInt24, meters)
        if has(2), let raw = reader.readUInt24LE() {
            out.totalDistanceMeters = Double(raw)
        } else if has(2) { return out }

        // Bit 3: Inclination and Ramp Angle (SInt16 + SInt16)
        if has(3) {
            if let inclineRaw = reader.readInt16LE() {
                out.inclinePercent = Double(inclineRaw) / 10.0
            } else { return out }
            if let rampRaw = reader.readInt16LE() {
                out.rampAngleDegrees = Double(rampRaw) / 10.0
            } else { return out }
        }

        // Bit 4: Positive Elevation Gain (UInt16, 0.1 meters)
        if has(4), let raw = reader.readUInt16LE() {
            out.positiveElevationGainMeters = Double(raw) / 10.0
        } else if has(4) { return out }

        // Bit 5: Negative Elevation Gain (UInt16, 0.1 meters)
        if has(5), let raw = reader.readUInt16LE() {
            out.negativeElevationGainMeters = Double(raw) / 10.0
        } else if has(5) { return out }

        // Bit 6: Instantaneous Pace (UInt16, 0.1 seconds per km)
        if has(6), let raw = reader.readUInt16LE() {
            out.instantaneousPaceSecondsPerKm = Double(raw) / 10.0
        } else if has(6) { return out }

        // Bit 7: Average Pace (UInt16, 0.1 seconds per km)
        if has(7), let raw = reader.readUInt16LE() {
            out.averagePaceSecondsPerKm = Double(raw) / 10.0
        } else if has(7) { return out }

        // Bit 8: Expended Energy (UInt16 + UInt16 + UInt8)
        if has(8) {
            guard let total = reader.readUInt16LE(),
                  let perHour = reader.readUInt16LE(),
                  let perMin = reader.readUInt8()
            else { return out }
            out.totalEnergyKcal = total
            out.energyPerHourKcal = perHour
            out.energyPerMinuteKcal = perMin
        }

        // Bit 9: Heart Rate (UInt8)
        if has(9), let raw = reader.readUInt8() {
            out.heartRateBpm = raw
        } else if has(9) { return out }

        // Bit 10: MET (UInt8, 0.1 METs)
        if has(10), let raw = reader.readUInt8() {
            out.metabolicEquivalent = Double(raw) / 10.0
        } else if has(10) { return out }

        // Bit 11: Elapsed Time (UInt16, seconds)
        if has(11), let raw = reader.readUInt16LE() {
            out.elapsedTimeSeconds = raw
        } else if has(11) { return out }

        // Bit 12: Remaining Time (UInt16, seconds)
        if has(12), let raw = reader.readUInt16LE() {
            out.remainingTimeSeconds = raw
        } else if has(12) { return out }

        // Bit 13: Force on Belt and Power Output (SInt16 + SInt16)
        if has(13) {
            if let forceRaw = reader.readInt16LE() {
                out.forceOnBeltNewtons = Double(forceRaw)
            } else { return out }
            if let powerRaw = reader.readInt16LE() {
                out.powerOutputWatts = Double(powerRaw)
            } else { return out }
        }

        return out
    }
}
