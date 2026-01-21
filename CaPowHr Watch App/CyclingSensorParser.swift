//
//  CyclingSensorParser.swift
//  CaPowHr Watch App
//
//  Parsing utilities for cycling-specific BLE profiles:
//  - Cycling Power Measurement (0x2A63)
//  - Cycling Speed and Cadence (CSC) Measurement (0x2A5B)
//  - FTMS Indoor Bike Data (0x2AD2)
//

import Foundation

// MARK: - IndoorBikeData

/// Parsed FTMS "Indoor Bike Data" (0x2AD2) fields.
/// All fields are optional (even mandatory ones) so truncated packets can be handled safely.
struct IndoorBikeData {
    // Mandatory (per spec), but optional here to allow safe parsing of truncated packets.
    var flags: UInt16?
    var instantaneousSpeedKph: Double?

    // Optional fields (presence controlled by Flags bit indices 1-12)
    var averageSpeedKph: Double?
    var instantaneousCadenceRpm: Double?
    var averageCadenceRpm: Double?
    var totalDistanceMeters: Double?
    var resistanceLevel: Int16?
    var instantaneousPowerWatts: Double?
    var averagePowerWatts: Double?

    // Expended Energy (bit 8)
    var totalEnergyKcal: UInt16?
    var energyPerHourKcal: UInt16?
    var energyPerMinuteKcal: UInt8?

    // Remaining optionals
    var heartRateBpm: UInt8?
    var metabolicEquivalent: Double? // 0.1 MET units
    var elapsedTimeSeconds: UInt16?
    var remainingTimeSeconds: UInt16?

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
}

/// Type alias for backward compatibility with existing code.
typealias FTMSData = IndoorBikeData

// MARK: - CyclingSensorParser

/// Parsing utilities for cycling BLE profiles.
enum CyclingSensorParser {
    
    // MARK: Cycling Power Measurement (0x2A63)
    
    /// Parse a Cycling Power Measurement payload (0x2A63) for instantaneous power.
    /// Per spec, the first two bytes are flags and the next two bytes are instantaneous power (Int16, watts).
    static func parsePowerMeasurement(_ data: Data) -> Double? {
        // Minimum valid length is 4 bytes: Flags (2) + Instantaneous Power (2).
        guard data.count >= 4 else { return nil }
        let instPower = data.subdata(in: 2..<4).withUnsafeBytes {
            Int16(littleEndian: $0.loadUnaligned(as: Int16.self))
        }
        return Double(instPower)
    }

    // MARK: CSC Measurement (0x2A5B)

    /// Compute cadence (RPM) from CSC crank revolution data with wrap-safe arithmetic.
    /// - Parameters:
    ///   - previousCount: Last cumulative crank revolution count (UInt16, wraps at 65535)
    ///   - previousTime: Last crank event time in 1/1024s ticks (UInt16, wraps at 65535)
    ///   - currentCount: Current cumulative crank revolution count
    ///   - currentTime: Current crank event time
    /// - Returns: Cadence in revolutions per minute, or nil if not enough information.
    static func computeCadenceRPM(previousCount: UInt16, previousTime: UInt16, currentCount: UInt16, currentTime: UInt16) -> Double? {
        guard previousCount != 0 else { return nil }
        let revDelta = UInt16(bitPattern: Int16(bitPattern: currentCount) &- Int16(bitPattern: previousCount))
        let timeDelta = UInt16(bitPattern: Int16(bitPattern: currentTime) &- Int16(bitPattern: previousTime))
        let ticks = Int(timeDelta)
        guard ticks > 0 else { return nil }
        let seconds = Double(ticks) / 1024.0
        return (Double(revDelta) / seconds) * 60.0
    }

    /// Parse Cycling Speed and Cadence (CSC) Measurement (0x2A5B).
    /// - Returns: Cumulative values (wheel/crank) that you can use to compute speed/cadence deltas.
    static func parseCSC(_ data: Data) -> (wheelRev: UInt32?, wheelTime: UInt16?, crankRev: UInt16?, crankTime: UInt16?) {
        var reader = BLEDataReader(data)

        guard let flags = reader.readUInt8() else { return (nil, nil, nil, nil) }

        var wheelRev: UInt32?
        var wheelTime: UInt16?
        var crankRev: UInt16?
        var crankTime: UInt16?

        // Bit 0: Wheel Revolution Data Present
        if (flags & 0x01) != 0 {
            wheelRev = reader.readUInt32LE()
            wheelTime = reader.readUInt16LE()
        }

        // Bit 1: Crank Revolution Data Present
        if (flags & 0x02) != 0 {
            crankRev = reader.readUInt16LE()
            crankTime = reader.readUInt16LE()
        }

        return (wheelRev, wheelTime, crankRev, crankTime)
    }

    // MARK: FTMS Indoor Bike Data (0x2AD2)

    /// Parse FTMS Indoor Bike Data (0x2AD2) and return selected fields.
    static func parseIndoorBikeData(_ data: Data) -> IndoorBikeData {
        var reader = BLEDataReader(data)
        var out = IndoorBikeData()

        // 1) FLAGS (mandatory)
        guard let flags = reader.readUInt16LE() else { return out }
        out.flags = flags

        // 2) INSTANTANEOUS SPEED (mandatory): UInt16, 0.01 km/h
        guard let speedRaw = reader.readUInt16LE() else { return out }
        out.instantaneousSpeedKph = Double(speedRaw) / 100.0

        // Helper: check bit index in flags
        func has(_ bitIndex: Int) -> Bool {
            (flags & (1 << bitIndex)) != 0
        }

        // 3) OPTIONAL FIELDS in spec order, bits 1 through 12 (bit 0 ignored)

        // Bit 1: Average Speed (UInt16, 0.01 km/h)
        if has(1), let raw = reader.readUInt16LE() {
            out.averageSpeedKph = Double(raw) / 100.0
        } else if has(1) { return out }

        // Bit 2: Instantaneous Cadence (UInt16, 0.5 RPM)
        if has(2), let raw = reader.readUInt16LE() {
            out.instantaneousCadenceRpm = Double(raw) / 2.0
        } else if has(2) { return out }

        // Bit 3: Average Cadence (UInt16, 0.5 RPM)
        if has(3), let raw = reader.readUInt16LE() {
            out.averageCadenceRpm = Double(raw) / 2.0
        } else if has(3) { return out }

        // Bit 4: Total Distance (UInt24, meters)
        if has(4), let raw = reader.readUInt24LE() {
            out.totalDistanceMeters = Double(raw)
        } else if has(4) { return out }

        // Bit 5: Resistance Level (SInt16)
        if has(5), let raw = reader.readInt16LE() {
            out.resistanceLevel = raw
        } else if has(5) { return out }

        // Bit 6: Instantaneous Power (SInt16, watts)
        if has(6), let raw = reader.readInt16LE() {
            out.instantaneousPowerWatts = Double(raw)
        } else if has(6) { return out }

        // Bit 7: Average Power (SInt16, watts)
        if has(7), let raw = reader.readInt16LE() {
            out.averagePowerWatts = Double(raw)
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

// MARK: - Backward Compatibility

/// Legacy namespace for backward compatibility. Prefer using `CyclingSensorParser` directly.
enum SensorDataParser {
    static func parsePowerMeasurement(_ data: Data) -> Double? {
        CyclingSensorParser.parsePowerMeasurement(data)
    }
    
    static func computeCadenceRPM(previousCount: UInt16, previousTime: UInt16, currentCount: UInt16, currentTime: UInt16) -> Double? {
        CyclingSensorParser.computeCadenceRPM(previousCount: previousCount, previousTime: previousTime, currentCount: currentCount, currentTime: currentTime)
    }
    
    static func parseCSC(_ data: Data) -> (wheelRev: UInt32?, wheelTime: UInt16?, crankRev: UInt16?, crankTime: UInt16?) {
        CyclingSensorParser.parseCSC(data)
    }
    
    static func parseFTMS(_ data: Data) -> FTMSData {
        CyclingSensorParser.parseIndoorBikeData(data)
    }
    
    static func parseTreadmillData(_ data: Data) -> TreadmillData {
        TreadmillSensorParser.parseTreadmillData(data)
    }
}
