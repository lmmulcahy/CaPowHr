//
//  CaPowHr_Watch_AppTests.swift
//  CaPowHr Watch AppTests
//
//  Created by Luke Mulcahy on 9/15/25.
//

import Testing
@testable import CaPowHr_Watch_App

struct CaPowHr_Watch_AppTests {

    private func dataFromHex(_ hex: String) -> Data {
        let cleaned = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\t", with: "")
        precondition(cleaned.count % 2 == 0, "Hex string must have even length")
        var bytes: [UInt8] = []
        bytes.reserveCapacity(cleaned.count / 2)
        var idx = cleaned.startIndex
        while idx < cleaned.endIndex {
            let next = cleaned.index(idx, offsetBy: 2)
            let byteStr = cleaned[idx..<next]
            let b = UInt8(byteStr, radix: 16)!
            bytes.append(b)
            idx = next
        }
        return Data(bytes)
    }

    @Test func ftmsIndoorBikeData_parsesPowerCadenceDistance() async throws {
        // Sample from user log:
        // flags = 0x0374 (little-endian 74 03)
        // speed raw = 0x0488
        // cadence raw = 0x0026 => 19 rpm
        // total distance = 0x000013 => 19 meters
        // inst power = 0x0014 => 20 watts
        let payload = dataFromHex("74038804260013000015001400000000000000")
        let parsed = SensorDataParser.parseFTMS(payload)

        #expect(parsed.instantaneousPowerWatts == 20)
        #expect(parsed.instantaneousCadenceRpm == 19)
        #expect(parsed.totalDistanceMeters == 19)
    }

    @Test func ftmsIndoorBikeData_parsesPriorBikeICSEPayload() async throws {
        // Sample from prior bike log (ICSE):
        // flags = 0x09FE (little-endian FE 09) => includes cadence, distance, inst power, and energy fields.
        // inst cadence raw = 0x0028 => 20 rpm
        // total distance (UInt24) = 0 meters in this particular frame
        // inst power raw = 0x0010 => 16 watts
        let payload = dataFromHex("fe098f044a002800030000000026001000000000004400010300")
        let parsed = SensorDataParser.parseFTMS(payload)

        #expect(parsed.instantaneousPowerWatts == 16)
        #expect(parsed.instantaneousCadenceRpm == 20)
        #expect(parsed.totalDistanceMeters == 0)
    }

}
