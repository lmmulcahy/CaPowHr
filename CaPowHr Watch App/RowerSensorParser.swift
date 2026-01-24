//
//  RowerSensorParser.swift
//  CaPowHr Watch App
//
//  Parsing utilities for rower-specific BLE profiles:
//  - FTMS Rower Data (0x2AD1)
//

import Foundation

// MARK: - RowerData

/// Parsed FTMS "Rower Data" (0x2AD1) fields.
/// All fields are optional to allow safe parsing of truncated or partial packets.
struct RowerData {
    // Mandatory (per spec), but optional here to allow safe parsing of truncated packets.
    var flags: UInt16?

    // Stroke Rate and Stroke Count (bit 0 = 0 means present, negated logic)
    var strokeRatePerMinute: Double?  // 0.5 stroke/min resolution
    var strokeCount: UInt16?

    // Optional fields (presence controlled by Flags bit indices 1-12)
    var averageStrokeRatePerMinute: Double?
    var totalDistanceMeters: Double?
    var instantaneousPaceSeconds500m: Double?  // seconds per 500m
    var averagePaceSeconds500m: Double?        // seconds per 500m
    var instantaneousPowerWatts: Double?
    var averagePowerWatts: Double?
    var resistanceLevel: Int16?

    // Expended Energy (bit 8)
    var totalEnergyKcal: UInt16?
    var energyPerHourKcal: UInt16?
    var energyPerMinuteKcal: UInt8?

    // Remaining optionals
    var heartRateBpm: UInt8?
    var metabolicEquivalent: Double? // 0.1 MET units
    var elapsedTimeSeconds: UInt16?
    var remainingTimeSeconds: UInt16?

    /// Convenience: pace in min:sec per 500m (derived from instantaneousPaceSeconds500m).
    var instantaneousPaceMinPer500m: Double? {
        guard let sec = instantaneousPaceSeconds500m else { return nil }
        return sec / 60.0
    }
    /// Convenience: pace in min:sec per 500m (derived from averagePaceSeconds500m).
    var averagePaceMinPer500m: Double? {
        guard let sec = averagePaceSeconds500m else { return nil }
        return sec / 60.0
    }
}

// MARK: - RowerSensorParser

/// Parsing utilities for rower BLE profiles.
enum RowerSensorParser {
    
    /// Parse FTMS Rower Data (0x2AD1) and return selected fields.
    /// Note: Unlike most FTMS characteristics, bit 0 uses negated logic:
    /// stroke rate and count are present when bit 0 is 0.
    static func parseRowerData(_ data: Data) -> RowerData {
        var reader = BLEDataReader(data)
        var out = RowerData()

        // 1) FLAGS (mandatory)
        guard let flags = reader.readUInt16LE() else { return out }
        out.flags = flags

        // Helper: check bit index in flags
        func has(_ bitIndex: Int) -> Bool {
            (flags & (1 << bitIndex)) != 0
        }

        // 2) STROKE RATE and STROKE COUNT (bit 0 = 0 means present, negated logic)
        // This is unusual compared to other FTMS characteristics
        if !has(0) {
            if let strokeRateRaw = reader.readUInt8() {
                out.strokeRatePerMinute = Double(strokeRateRaw) / 2.0
            } else { return out }
            if let strokeCountRaw = reader.readUInt16LE() {
                out.strokeCount = strokeCountRaw
            } else { return out }
        }

        // 3) OPTIONAL FIELDS in spec order, bits 1 through 12

        // Bit 1: Average Stroke Rate (UInt8, 0.5 strokes/min)
        if has(1), let raw = reader.readUInt8() {
            out.averageStrokeRatePerMinute = Double(raw) / 2.0
        } else if has(1) { return out }

        // Bit 2: Total Distance (UInt24, meters)
        if has(2), let raw = reader.readUInt24LE() {
            out.totalDistanceMeters = Double(raw)
        } else if has(2) { return out }

        // Bit 3: Instantaneous Pace (UInt16, seconds per 500m)
        if has(3), let raw = reader.readUInt16LE() {
            out.instantaneousPaceSeconds500m = Double(raw)
        } else if has(3) { return out }

        // Bit 4: Average Pace (UInt16, seconds per 500m)
        if has(4), let raw = reader.readUInt16LE() {
            out.averagePaceSeconds500m = Double(raw)
        } else if has(4) { return out }

        // Bit 5: Instantaneous Power (SInt16, watts)
        if has(5), let raw = reader.readInt16LE() {
            out.instantaneousPowerWatts = Double(raw)
        } else if has(5) { return out }

        // Bit 6: Average Power (SInt16, watts)
        if has(6), let raw = reader.readInt16LE() {
            out.averagePowerWatts = Double(raw)
        } else if has(6) { return out }

        // Bit 7: Resistance Level (SInt16)
        if has(7), let raw = reader.readInt16LE() {
            out.resistanceLevel = raw
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

        return out
    }
}
