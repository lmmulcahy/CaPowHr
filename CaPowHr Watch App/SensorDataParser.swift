import Foundation

struct FTMSData {
    var instantaneousSpeedMps: Double?
    var instantaneousCadenceRpm: Double?
    var instantaneousPowerWatts: Double?
    var totalDistanceMeters: Double?
}

enum SensorDataParser {
    static func parsePowerMeasurement(_ data: Data) -> Double? {
        guard data.count >= 2 else { return nil }
        let watts = data.subdata(in: 0..<2).withUnsafeBytes { $0.load(as: UInt16.self) }
        return Double(watts)
    }

    static func computeCadenceRPM(previousCount: UInt16, previousTime: UInt16, currentCount: UInt16, currentTime: UInt16) -> Double? {
        guard previousCount != 0 else { return nil }
        let revDelta = UInt16(bitPattern: Int16(bitPattern: currentCount) &- Int16(bitPattern: previousCount))
        let timeDelta = UInt16(bitPattern: Int16(bitPattern: currentTime) &- Int16(bitPattern: previousTime))
        let ticks = Int(timeDelta)
        guard ticks > 0 else { return nil }
        let seconds = Double(ticks) / 1024.0
        return (Double(revDelta) / seconds) * 60.0
    }

    static func parseFTMS(_ data: Data) -> FTMSData {
        var result = FTMSData()
        guard data.count >= 2 else { return result }
        let flags = UInt16(data[0]) | (UInt16(data[1]) << 8)
        var offset = 2
        func readUInt16() -> UInt16? { guard data.count >= offset + 2 else { return nil }; defer { offset += 2 }; return data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: UInt16.self) } }
        func readInt16() -> Int16? { guard data.count >= offset + 2 else { return nil }; defer { offset += 2 }; return data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: Int16.self) } }
        func readUInt8() -> UInt8? { guard data.count > offset else { return nil }; defer { offset += 1 }; return data[offset] }
        func readUInt24() -> UInt32? { guard data.count >= offset + 3 else { return nil }; let b0 = UInt32(data[offset]); let b1 = UInt32(data[offset+1]); let b2 = UInt32(data[offset+2]); offset += 3; return b0 | (b1 << 8) | (b2 << 16) }

        if (flags & 0x0002) != 0, let instSpeedRaw = readUInt16() {
            result.instantaneousSpeedMps = Double(instSpeedRaw) / 100.0
        }
        if (flags & 0x0004) != 0 { _ = readUInt16() }
        if (flags & 0x0008) != 0, let cadenceHalf = readUInt16() {
            result.instantaneousCadenceRpm = Double(cadenceHalf) / 2.0
        }
        if (flags & 0x0010) != 0 { _ = readUInt16() }
        if (flags & 0x0020) != 0, let totalDistance = readUInt24() {
            result.totalDistanceMeters = Double(totalDistance)
        }
        if (flags & 0x0040) != 0 { _ = readInt16() }
        if (flags & 0x0080) != 0, let instPower = readInt16() {
            result.instantaneousPowerWatts = Double(instPower)
        }
        if (flags & 0x0100) != 0 { _ = readInt16() }
        if (flags & 0x0200) != 0 { _ = readUInt16() }
        if (flags & 0x0400) != 0 { _ = readUInt16() }
        if (flags & 0x0800) != 0 { _ = readUInt8() }
        if (flags & 0x1000) != 0 { _ = readUInt8() }
        if (flags & 0x2000) != 0 { _ = readUInt8() }
        if (flags & 0x4000) != 0 { _ = readUInt16() }
        if (flags & 0x8000) != 0 { _ = readUInt16() }

        return result
    }
}


