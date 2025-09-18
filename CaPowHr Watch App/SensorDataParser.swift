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
// - Speed from FTMS Indoor Bike Data is in 0.01 m/s units (UInt16), so m/s = raw / 100.
// - Distance from FTMS Indoor Bike Data is in UInt24 meters (3 bytes, little-endian).
// - Power values are in watts. FTMS power is Int16; Cycling Power Measurement example here treats first 2 bytes as instantaneous power UInt16.

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
    /// This implementation assumes the first two bytes are instantaneous power in watts.
    /// If a device includes flags and additional fields, extend this to decode by spec flags.
    static func parsePowerMeasurement(_ data: Data) -> Double? {
        guard data.count >= 2 else { return nil }
        let watts = data.subdata(in: 0..<2).withUnsafeBytes { $0.load(as: UInt16.self) }
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
    /// - Instantaneous Speed (0x0002): UInt16 in 0.01 m/s
    /// - Average Speed (0x0004): ignored
    /// - Instantaneous Cadence (0x0008): UInt16 in 0.5 RPM
    /// - Average Cadence (0x0010): ignored
    /// - Total Distance (0x0020): UInt24 in meters
    /// - Resistance Level (0x0040): ignored
    /// - Instantaneous Power (0x0080): Int16 in watts
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

        // 0x0002: Instantaneous Speed present (UInt16, scale 0.01 m/s)
        if (flags & 0x0002) != 0, let instSpeedRaw = readUInt16() {
            // Convert raw to meters/second
            result.instantaneousSpeedMps = Double(instSpeedRaw) / 100.0
        }
        // 0x0004: Average Speed present (UInt16, 0.01 m/s) — read and ignore
        if (flags & 0x0004) != 0 { _ = readUInt16() }
        // 0x0008: Instantaneous Cadence present (UInt16, 0.5 RPM units)
        if (flags & 0x0008) != 0, let cadenceHalf = readUInt16() {
            // Convert 0.5 RPM units to RPM
            result.instantaneousCadenceRpm = Double(cadenceHalf) / 2.0
        }
        // 0x0010: Average Cadence present — read and ignore
        if (flags & 0x0010) != 0 { _ = readUInt16() }
        // 0x0020: Total Distance present (UInt24, meters)
        if (flags & 0x0020) != 0, let totalDistance = readUInt24() {
            result.totalDistanceMeters = Double(totalDistance)
        }
        // 0x0040: Resistance Level present — read and ignore
        if (flags & 0x0040) != 0 { _ = readInt16() }
        // 0x0080: Instantaneous Power present (Int16, watts)
        if (flags & 0x0080) != 0, let instPower = readInt16() {
            result.instantaneousPowerWatts = Double(instPower)
        }
        // 0x0100: Average Power present — read and ignore
        if (flags & 0x0100) != 0 { _ = readInt16() }
        // 0x0200: Total Energy present — read and ignore (units vary by vendor)
        if (flags & 0x0200) != 0 { _ = readUInt16() }
        // 0x0400: Energy Per Hour present — read and ignore
        if (flags & 0x0400) != 0 { _ = readUInt16() }
        // 0x0800: Energy Per Minute present — read and ignore
        if (flags & 0x0800) != 0 { _ = readUInt8() }
        // 0x1000: Heart Rate present — read and ignore to avoid conflicts with watch HR
        if (flags & 0x1000) != 0 { _ = readUInt8() }
        // 0x2000: MET present — read and ignore
        if (flags & 0x2000) != 0 { _ = readUInt8() }
        // 0x4000: Elapsed Time present — read and ignore (UInt16 seconds)
        if (flags & 0x4000) != 0 { _ = readUInt16() }
        // 0x8000: Remaining Time present — read and ignore (UInt16 seconds)
        if (flags & 0x8000) != 0 { _ = readUInt16() }

        return result
    }
}


