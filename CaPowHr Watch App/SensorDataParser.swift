import Foundation

// MARK: - SensorDataParser
//
// Centralized, well-documented parsing utilities for common cycling BLE profiles:
// - Cycling Power Measurement (Characteristic UUID 0x2A63)
// - Cycling Speed and Cadence (CSC) Measurement (Characteristic UUID 0x2A5B)
// - Fitness Machine Service (FTMS) Indoor Bike Data (Characteristic UUID 0x2AD2)
//
// Notes on BLE value encoding (per Bluetooth SIG specs):
// - All multi-byte integer fields are little-endian.
// - Unless otherwise stated, time fields in CSC are in 1/1024 second ticks and wrap at UInt16.
// - Cadence from FTMS Indoor Bike Data is in 0.5 RPM units (UInt16), so rpm = raw / 2.
// - Speed from FTMS Indoor Bike Data is in 0.01 km/h units (UInt16), so m/s = (raw / 100) / 3.6.
// - Distance from FTMS Indoor Bike Data is in UInt24 meters (3 bytes, little-endian).
// - Power values are in watts. FTMS power is Int16. Cycling Power Measurement (2A63) instantaneous power is Int16 after a 2-byte flags field.

/// Parsed FTMS "Indoor Bike Data" (0x2AD2) fields.
/// All fields are optional (even mandatory ones) so truncated packets can be handled safely.
struct FTMSData {
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

/// A namespace for pure parsing helpers. These functions are deterministic and side-effect free.
enum SensorDataParser {
    /// Parse a Cycling Power Measurement payload (0x2A63) for instantaneous power.
    /// Per spec, the first two bytes are flags and the next two bytes are instantaneous power (Int16, watts).
    static func parsePowerMeasurement(_ data: Data) -> Double? {
        // Minimum valid length is 4 bytes: Flags (2) + Instantaneous Power (2).
        // If data is truncated (< 4), it may contain flags only; treating those bytes as power is incorrect.
        guard data.count >= 4 else { return nil }
        let instPower = data.subdata(in: 2..<4).withUnsafeBytes {
            Int16(littleEndian: $0.loadUnaligned(as: Int16.self))
        }
        return Double(instPower)
    }

    /// Compute cadence (RPM) from CSC crank revolution data with wrap-safe arithmetic.
    /// - Parameters:
    ///   - previousCount: Last cumulative crank revolution count (UInt16, wraps at 65535)
    ///   - previousTime: Last crank event time in 1/1024s ticks (UInt16, wraps at 65535)
    ///   - currentCount: Current cumulative crank revolution count
    ///   - currentTime: Current crank event time
    /// - Returns: Cadence in revolutions per minute, or nil if not enough information.
    ///
    /// The spec provides cumulative counters (not deltas). To handle wrap-around correctly,
    /// we compute the delta using Int16 subtraction then cast back to UInt16. This yields the
    /// correct modular difference even when the 16-bit counters wrap.
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
    ///   Crank values can be passed to `computeCadenceRPM(previousCount:previousTime:currentCount:currentTime:)`.
    ///
    /// Packet format (per spec):
    /// - Flags (UInt8)
    /// - If flags bit 0 set: Cumulative Wheel Revolutions (UInt32) + Last Wheel Event Time (UInt16)
    /// - If flags bit 1 set: Cumulative Crank Revolutions (UInt16) + Last Crank Event Time (UInt16)
    static func parseCSC(_ data: Data) -> (wheelRev: UInt32?, wheelTime: UInt16?, crankRev: UInt16?, crankTime: UInt16?) {
        var cursor = 0

        func readUInt8() -> UInt8? {
            guard data.count >= cursor + 1 else { return nil }
            defer { cursor += 1 }
            return data[cursor]
        }
        func readUInt16LE() -> UInt16? {
            guard data.count >= cursor + 2 else { return nil }
            defer { cursor += 2 }
            return data.subdata(in: cursor..<(cursor + 2)).withUnsafeBytes {
                UInt16(littleEndian: $0.loadUnaligned(as: UInt16.self))
            }
        }
        func readUInt32LE() -> UInt32? {
            guard data.count >= cursor + 4 else { return nil }
            defer { cursor += 4 }
            return data.subdata(in: cursor..<(cursor + 4)).withUnsafeBytes {
                UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))
            }
        }

        guard let flags = readUInt8() else { return (nil, nil, nil, nil) }

        var wheelRev: UInt32?
        var wheelTime: UInt16?
        var crankRev: UInt16?
        var crankTime: UInt16?

        // Bit 0: Wheel Revolution Data Present
        if (flags & 0x01) != 0 {
            wheelRev = readUInt32LE()
            wheelTime = readUInt16LE()
        }

        // Bit 1: Crank Revolution Data Present
        if (flags & 0x02) != 0 {
            crankRev = readUInt16LE()
            crankTime = readUInt16LE()
        }

        return (wheelRev, wheelTime, crankRev, crankTime)
    }

    /// Parse FTMS Indoor Bike Data (0x2AD2) and return selected fields.
    ///
    /// Flags (16-bit) indicate which fields are present. This parser reads:
    /// Per spec, the packet is:
    /// - Flags (UInt16) [mandatory]
    /// - Instantaneous Speed (UInt16, 0.01 km/h) [mandatory]
    /// - Optional fields in strict order, controlled by Flags bit indices 1-12.
    static func parseFTMS(_ data: Data) -> FTMSData {
        // Cursor starts at 0 (requirement)
        var cursor = 0
        var out = FTMSData()

        func readUInt8() -> UInt8? {
            guard data.count >= cursor + 1 else { return nil }
            defer { cursor += 1 }
            return data[cursor]
        }
        func readUInt16LE() -> UInt16? {
            guard data.count >= cursor + 2 else { return nil }
            defer { cursor += 2 }
            return data.subdata(in: cursor..<(cursor + 2)).withUnsafeBytes {
                UInt16(littleEndian: $0.loadUnaligned(as: UInt16.self))
            }
        }
        func readInt16LE() -> Int16? {
            guard data.count >= cursor + 2 else { return nil }
            defer { cursor += 2 }
            return data.subdata(in: cursor..<(cursor + 2)).withUnsafeBytes {
                Int16(littleEndian: $0.loadUnaligned(as: Int16.self))
            }
        }
        func readUInt24LE() -> UInt32? {
            guard data.count >= cursor + 3 else { return nil }
            let b0 = UInt32(data[cursor])
            let b1 = UInt32(data[cursor + 1])
            let b2 = UInt32(data[cursor + 2])
            cursor += 3
            return b0 | (b1 << 8) | (b2 << 16)
        }

        // 1) FLAGS (mandatory)
        guard let flags = readUInt16LE() else { return out }
        out.flags = flags

        // 2) INSTANTANEOUS SPEED (mandatory): UInt16, 0.01 km/h
        guard let speedRaw = readUInt16LE() else { return out }
        out.instantaneousSpeedKph = Double(speedRaw) / 100.0

        // Helper: check bit index in flags
        func has(_ bitIndex: Int) -> Bool {
            (flags & (1 << bitIndex)) != 0
        }

        // 3) OPTIONAL FIELDS in spec order, bits 1 through 12 (bit 0 ignored)

        // Bit 1: Average Speed (UInt16, 0.01 km/h)
        if has(1), let raw = readUInt16LE() {
            out.averageSpeedKph = Double(raw) / 100.0
        } else if has(1) { return out }

        // Bit 2: Instantaneous Cadence (UInt16, 0.5 RPM)
        if has(2), let raw = readUInt16LE() {
            out.instantaneousCadenceRpm = Double(raw) / 2.0
        } else if has(2) { return out }

        // Bit 3: Average Cadence (UInt16, 0.5 RPM)
        if has(3), let raw = readUInt16LE() {
            out.averageCadenceRpm = Double(raw) / 2.0
        } else if has(3) { return out }

        // Bit 4: Total Distance (UInt24, meters)
        if has(4), let raw = readUInt24LE() {
            out.totalDistanceMeters = Double(raw)
        } else if has(4) { return out }

        // Bit 5: Resistance Level (SInt16)
        if has(5), let raw = readInt16LE() {
            out.resistanceLevel = raw
        } else if has(5) { return out }

        // Bit 6: Instantaneous Power (SInt16, watts)
        if has(6), let raw = readInt16LE() {
            out.instantaneousPowerWatts = Double(raw)
        } else if has(6) { return out }

        // Bit 7: Average Power (SInt16, watts)
        if has(7), let raw = readInt16LE() {
            out.averagePowerWatts = Double(raw)
        } else if has(7) { return out }

        // Bit 8: Expended Energy (UInt16 + UInt16 + UInt8)
        if has(8) {
            guard let total = readUInt16LE(),
                  let perHour = readUInt16LE(),
                  let perMin = readUInt8()
            else { return out }
            out.totalEnergyKcal = total
            out.energyPerHourKcal = perHour
            out.energyPerMinuteKcal = perMin
        }

        // Bit 9: Heart Rate (UInt8)
        if has(9), let raw = readUInt8() {
            out.heartRateBpm = raw
        } else if has(9) { return out }

        // Bit 10: MET (UInt8, 0.1 METs)
        if has(10), let raw = readUInt8() {
            out.metabolicEquivalent = Double(raw) / 10.0
        } else if has(10) { return out }

        // Bit 11: Elapsed Time (UInt16, seconds)
        if has(11), let raw = readUInt16LE() {
            out.elapsedTimeSeconds = raw
        } else if has(11) { return out }

        // Bit 12: Remaining Time (UInt16, seconds)
        if has(12), let raw = readUInt16LE() {
            out.remainingTimeSeconds = raw
        } else if has(12) { return out }

        return out
    }
}


