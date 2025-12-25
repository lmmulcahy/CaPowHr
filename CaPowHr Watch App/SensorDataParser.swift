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

/// Parsed subset of FTMS (Indoor Bike Data) fields we care about.
/// Omitted fields are ignored upstream and can be added here as needed.
struct FTMSData {
    var instantaneousSpeedMps: Double?
    var instantaneousCadenceRpm: Double?
    var instantaneousPowerWatts: Double?
    var totalDistanceMeters: Double?
}

/// A namespace for pure parsing helpers. These functions are deterministic and side-effect free.
enum SensorDataParser {
    /// Parse a Cycling Power Measurement payload (0x2A63) for instantaneous power.
    /// Per spec, the first two bytes are flags and the next two bytes are instantaneous power (Int16, watts).
    /// Some devices may send a truncated payload (power only); we keep a fallback for that case.
    static func parsePowerMeasurement(_ data: Data) -> Double? {
        if data.count >= 4 {
            let instPower = data.subdata(in: 2..<4).withUnsafeBytes { $0.load(as: Int16.self) }
            return Double(instPower)
        }
        guard data.count >= 2 else { return nil }
        let watts = data.subdata(in: 0..<2).withUnsafeBytes { $0.load(as: Int16.self) }
        return Double(watts)
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

    /// Parse FTMS Indoor Bike Data (0x2AD2) and return selected fields.
    ///
    /// Flags (16-bit) indicate which fields are present. This parser reads:
    /// - Instantaneous Speed (always present): UInt16 in 0.01 km/h
    /// - Average Speed (0x0002): ignored
    /// - Instantaneous Cadence (0x0004): UInt16 in 0.5 RPM
    /// - Average Cadence (0x0008): ignored
    /// - Total Distance (0x0010): UInt24 in meters
    /// - Resistance Level (0x0020): ignored
    /// - Instantaneous Power (0x0040): Int16 in watts
    /// Remaining flags are ignored but can be added as needed.
    static func parseFTMS(_ data: Data) -> FTMSData {
        // Accumulator for parsed values
        var result = FTMSData()
        // Minimum payload is 2-byte flags; bail out if shorter
        guard data.count >= 2 else { return result }
        // Flags are 16-bit little-endian (LSB first)
        let flags = UInt16(data[0]) | (UInt16(data[1]) << 8)
        // Cursor into the variable-length payload following flags
        var offset = 2
        
        // Per FTMS spec, Instantaneous Speed is always present immediately after Flags.
        // Speed is UInt16 in 0.01 km/h.
        if data.count >= offset + 2 {
            let speedRaw = data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: UInt16.self) }
            offset += 2
            let kmh = Double(speedRaw) / 100.0
            result.instantaneousSpeedMps = kmh / 3.6
        } else {
            return result
        }
        
        // Helper: read a little-endian UInt16 from current offset and advance cursor
        func readUInt16() -> UInt16? {
            guard data.count >= offset + 2 else { return nil }
            defer { offset += 2 }
            return data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: UInt16.self) }
        }
        // Helper: read a little-endian Int16 and advance cursor
        func readInt16() -> Int16? {
            guard data.count >= offset + 2 else { return nil }
            defer { offset += 2 }
            return data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: Int16.self) }
        }
        // Helper: read a single byte and advance cursor
        func readUInt8() -> UInt8? {
            guard data.count > offset else { return nil }
            defer { offset += 1 }
            return data[offset]
        }
        // Helper: read a 24-bit unsigned int (little-endian: b0 + b1<<8 + b2<<16) and advance cursor
        func readUInt24() -> UInt32? {
            guard data.count >= offset + 3 else { return nil }
            let b0 = UInt32(data[offset])
            let b1 = UInt32(data[offset+1])
            let b2 = UInt32(data[offset+2])
            offset += 3
            return b0 | (b1 << 8) | (b2 << 16)
        }

        // FTMS Indoor Bike Data flag bits we care about (bit 0 is "More Data", ignored here).
        let averageSpeedPresent: UInt16 = 1 << 1   // 0x0002
        let instantaneousCadencePresent: UInt16 = 1 << 2 // 0x0004
        let averageCadencePresent: UInt16 = 1 << 3  // 0x0008
        let totalDistancePresent: UInt16 = 1 << 4   // 0x0010
        let resistanceLevelPresent: UInt16 = 1 << 5 // 0x0020
        let instantaneousPowerPresent: UInt16 = 1 << 6 // 0x0040
        let averagePowerPresent: UInt16 = 1 << 7    // 0x0080
        let totalEnergyPresent: UInt16 = 1 << 8     // 0x0100
        let heartRatePresent: UInt16 = 1 << 9       // 0x0200
        let metPresent: UInt16 = 1 << 10            // 0x0400
        let elapsedTimePresent: UInt16 = 1 << 11    // 0x0800
        let remainingTimePresent: UInt16 = 1 << 12  // 0x1000

        // 0x0002: Average Speed present (UInt16, 0.01 km/h) — read and ignore
        if (flags & averageSpeedPresent) != 0 { _ = readUInt16() }

        // 0x0004: Instantaneous Cadence present (UInt16, 0.5 RPM units)
        if (flags & instantaneousCadencePresent) != 0, let cadenceHalf = readUInt16() {
            // Convert 0.5 RPM units to RPM
            result.instantaneousCadenceRpm = Double(cadenceHalf) / 2.0
        }

        // 0x0008: Average Cadence present — read and ignore
        if (flags & averageCadencePresent) != 0 { _ = readUInt16() }

        // 0x0010: Total Distance present (UInt24, meters)
        if (flags & totalDistancePresent) != 0, let totalDistance = readUInt24() {
            result.totalDistanceMeters = Double(totalDistance)
        }

        // 0x0020: Resistance Level present — read and ignore
        if (flags & resistanceLevelPresent) != 0 { _ = readInt16() }

        // 0x0040: Instantaneous Power present (Int16, watts)
        if (flags & instantaneousPowerPresent) != 0, let instPower = readInt16() {
            result.instantaneousPowerWatts = Double(instPower)
        }

        // 0x0080: Average Power present — read and ignore
        if (flags & averagePowerPresent) != 0 { _ = readInt16() }

        // 0x0100: Expended Energy present (Total Energy UInt16, Energy/Hour UInt16, Energy/Minute UInt8) — read and ignore
        if (flags & totalEnergyPresent) != 0 {
            _ = readUInt16()
            _ = readUInt16()
            _ = readUInt8()
        }

        // 0x0200: Heart Rate present — read and ignore to avoid conflicts with watch HR
        if (flags & heartRatePresent) != 0 { _ = readUInt8() }

        // 0x0400: MET present — read and ignore
        if (flags & metPresent) != 0 { _ = readUInt8() }

        // 0x0800: Elapsed Time present — read and ignore (UInt16 seconds)
        if (flags & elapsedTimePresent) != 0 { _ = readUInt16() }

        // 0x1000: Remaining Time present — read and ignore (UInt16 seconds)
        if (flags & remainingTimePresent) != 0 { _ = readUInt16() }

        return result
    }
}


