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

    private static func buildMinimalFIT(summary: WorkoutSummaryData) -> Data {
        var buffer = Data()

        // FIT file header (14 bytes)
        buffer.append(contentsOf: [0x0E, 0x10, 0xD9, 0x07]) // header size + protocol version + profile version
        let dataSizeOffset = buffer.count
        buffer.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // data size placeholder
        buffer.append(contentsOf: Array(".FIT".utf8))
        buffer.append(contentsOf: [0x00, 0x00]) // CRC placeholder

        // File ID message (mesg num 0)
        buffer.append(contentsOf: encodeMessage(
            localMesg: 0,
            globalMesg: 0,
            fields: [
                (0, encodeEnum(4)), // type = activity
                (1, encodeUInt32(1)), // manufacturer = development
                (2, encodeUInt16(0)), // product
                (3, encodeUInt32Z(summary.startDate)),
                (4, encodeUInt32Z(Date()))
            ]
        ))

        // Session message (mesg num 18)
        buffer.append(contentsOf: encodeMessage(
            localMesg: 1,
            globalMesg: 18,
            fields: [
                (0, encodeEnum(sportEnum(for: summary.workoutType))),
                (1, encodeUInt32Z(summary.startDate)),
                (2, encodeUInt32Z(summary.startDate.addingTimeInterval(summary.durationSeconds))),
                (7, encodeUInt32(UInt32(summary.durationSeconds * 1000))), // total_elapsed_time in ms
                (9, encodeUInt32(UInt32(summary.distanceMeters * 100))), // total_distance in cm
                (19, encodeUInt8(0)) // trigger = activity end
            ]
        ))

        // Activity message (mesg num 34)
        buffer.append(contentsOf: encodeMessage(
            localMesg: 2,
            globalMesg: 34,
            fields: [
                (0, encodeUInt32Z(summary.startDate)),
                (1, encodeUInt16(1)), // num_sessions
                (5, encodeEnum(0)) // type = manual
            ]
        ))

        let dataSize = UInt32(buffer.count - 14)
        buffer.replaceSubrange(dataSizeOffset..<(dataSizeOffset + 4), with: encodeUInt32(dataSize))

        let crc = fitCRC(buffer)
        buffer.append(contentsOf: encodeUInt16(crc))
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

    private static func encodeMessage(localMesg: UInt8, globalMesg: UInt16, fields: [(UInt8, Data)]) -> Data {
        var out = Data()
        let definition = Data([
            0x40 | localMesg,
            0x00,
            UInt8(globalMesg & 0xFF),
            UInt8((globalMesg >> 8) & 0xFF),
            UInt8(fields.count)
        ] + fields.flatMap { field -> [UInt8] in
            [field.0, UInt8(field.1.count), 0x00]
        })
        out.append(definition)

        var message = Data([localMesg])
        for field in fields {
            message.append(field.1)
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

    private static func encodeUInt32Z(_ date: Date) -> Data {
        let fitEpoch = Date(timeIntervalSince1970: 631065600) // 1989-12-31 UTC
        let seconds = UInt32(max(0, date.timeIntervalSince(fitEpoch)))
        return encodeUInt32(seconds)
    }

    private static func fitCRC(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0
        for byte in data {
            var tmp = UInt16(byte) << 8
            for _ in 0..<8 {
                if (crc ^ tmp) & 0x8000 != 0 {
                    crc = (crc << 1) ^ 0xCC01
                } else {
                    crc <<= 1
                }
                tmp <<= 1
            }
        }
        return crc
    }
}
