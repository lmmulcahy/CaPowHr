import Foundation

enum FITExporter {
    /// Writes a minimal FIT activity file containing session summary data.
    static func exportWorkout(_ summary: WorkoutSummaryData) throws -> URL {
        let fileName = "CaPowHr-\(Int(summary.startDate.timeIntervalSince1970)).fit"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let data = buildMinimalFIT(summary: summary)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// FIT base type codes (FIT Protocol §4.2.1.4). The high bit marks
    /// multi-byte endian-sensitive types.
    private enum BaseType {
        static let enumType: UInt8 = 0x00
        static let uint8: UInt8 = 0x02
        static let uint16: UInt8 = 0x84
        static let uint32: UInt8 = 0x86
    }

    /// One field of a FIT data message: global field number, base type, encoded value.
    private typealias Field = (number: UInt8, baseType: UInt8, data: Data)

    // Internal for unit testing.
    static func buildMinimalFIT(summary: WorkoutSummaryData) -> Data {
        var buffer = Data()

        // FIT file header (14 bytes)
        buffer.append(contentsOf: [0x0E, 0x10, 0xD9, 0x07]) // header size + protocol version + profile version
        let dataSizeOffset = buffer.count
        buffer.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // data size placeholder
        buffer.append(contentsOf: Array(".FIT".utf8))
        let headerCRCOffset = buffer.count
        buffer.append(contentsOf: [0x00, 0x00]) // header CRC placeholder

        let endDate = summary.startDate.addingTimeInterval(summary.durationSeconds)
        let elapsedMs = UInt32(max(0, summary.durationSeconds) * 1000)

        // File ID message (mesg num 0)
        buffer.append(encodeMessage(
            localMesg: 0,
            globalMesg: 0,
            fields: [
                (0, BaseType.enumType, encodeEnum(4)),        // type = activity
                (1, BaseType.uint16, encodeUInt16(255)),      // manufacturer = development
                (2, BaseType.uint16, encodeUInt16(0)),        // product
                (4, BaseType.uint32, encodeFITTimestamp(Date())) // time_created
            ]
        ))

        // Session message (mesg num 18)
        var sessionFields: [Field] = [
            (253, BaseType.uint32, encodeFITTimestamp(endDate)),          // timestamp
            (2, BaseType.uint32, encodeFITTimestamp(summary.startDate)),  // start_time
            (5, BaseType.enumType, encodeEnum(sportEnum(for: summary.workoutType))), // sport
            (7, BaseType.uint32, encodeUInt32(elapsedMs)),                // total_elapsed_time (ms)
            (8, BaseType.uint32, encodeUInt32(elapsedMs)),                // total_timer_time (ms)
            (9, BaseType.uint32, encodeUInt32(UInt32(max(0, summary.distanceMeters) * 100))) // total_distance (cm)
        ]
        if let hr = summary.averageHeartRate, hr > 0 {
            sessionFields.append((16, BaseType.uint8, encodeUInt8(UInt8(min(hr, 255))))) // avg_heart_rate
        }
        if let cadence = summary.averageCadence, cadence > 0 {
            sessionFields.append((18, BaseType.uint8, encodeUInt8(UInt8(min(cadence, 255))))) // avg_cadence
        }
        if let power = summary.averagePower, power > 0 {
            sessionFields.append((20, BaseType.uint16, encodeUInt16(UInt16(min(power, 65534))))) // avg_power
        }
        buffer.append(encodeMessage(localMesg: 1, globalMesg: 18, fields: sessionFields))

        // Activity message (mesg num 34)
        buffer.append(encodeMessage(
            localMesg: 2,
            globalMesg: 34,
            fields: [
                (253, BaseType.uint32, encodeFITTimestamp(endDate)), // timestamp
                (0, BaseType.uint32, encodeUInt32(elapsedMs)),       // total_timer_time (ms)
                (1, BaseType.uint16, encodeUInt16(1)),               // num_sessions
                (2, BaseType.enumType, encodeEnum(0))                // type = manual
            ]
        ))

        let dataSize = UInt32(buffer.count - 14)
        buffer.replaceSubrange(dataSizeOffset..<(dataSizeOffset + 4), with: encodeUInt32(dataSize))

        // Header CRC covers the first 12 header bytes; file CRC covers everything before it.
        let headerCRC = fitCRC(buffer.prefix(12))
        buffer.replaceSubrange(headerCRCOffset..<(headerCRCOffset + 2), with: encodeUInt16(headerCRC))
        let crc = fitCRC(buffer)
        buffer.append(encodeUInt16(crc))
        return buffer
    }

    private static func sportEnum(for type: WorkoutType) -> UInt8 {
        switch type {
        case .indoorCycle: return 2 // cycling
        case .indoorRun: return 1 // running
        case .indoorWalk: return 11 // walking
        case .indoorRow: return 15 // rowing
        }
    }

    private static func encodeMessage(localMesg: UInt8, globalMesg: UInt16, fields: [Field]) -> Data {
        var out = Data()
        let definition = Data([
            0x40 | localMesg,
            0x00,
            0x00, // architecture = little-endian
            UInt8(globalMesg & 0xFF),
            UInt8((globalMesg >> 8) & 0xFF),
            UInt8(fields.count)
        ] + fields.flatMap { field -> [UInt8] in
            [field.number, UInt8(field.data.count), field.baseType]
        })
        out.append(definition)

        var message = Data([localMesg])
        for field in fields {
            message.append(field.data)
        }
        out.append(message)
        return out
    }

    private static func encodeUInt8(_ value: UInt8) -> Data { Data([value]) }
    private static func encodeEnum(_ value: UInt8) -> Data { Data([value]) }

    private static func encodeUInt16(_ value: UInt16) -> Data {
        var v = value.littleEndian
        return Data(bytes: &v, count: 2)
    }

    private static func encodeUInt32(_ value: UInt32) -> Data {
        var v = value.littleEndian
        return Data(bytes: &v, count: 4)
    }

    /// FIT date_time: seconds since the FIT epoch (1989-12-31T00:00:00Z), uint32.
    private static func encodeFITTimestamp(_ date: Date) -> Data {
        let fitEpoch = Date(timeIntervalSince1970: 631065600)
        let seconds = UInt32(max(0, date.timeIntervalSince(fitEpoch)))
        return encodeUInt32(seconds)
    }

    /// FIT CRC-16 (CRC-16/ARC), nibble-table implementation from the FIT SDK reference.
    static func fitCRC(_ data: Data) -> UInt16 {
        let table: [UInt16] = [
            0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
            0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400
        ]
        var crc: UInt16 = 0
        for byte in data {
            var tmp = table[Int(crc & 0xF)]
            crc = (crc >> 4) & 0x0FFF
            crc = crc ^ tmp ^ table[Int(byte & 0xF)]

            tmp = table[Int(crc & 0xF)]
            crc = (crc >> 4) & 0x0FFF
            crc = crc ^ tmp ^ table[Int((byte >> 4) & 0xF)]
        }
        return crc
    }
}
