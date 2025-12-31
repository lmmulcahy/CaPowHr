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

        #expect(parsed.flags == 0x0374)
        #expect(parsed.instantaneousSpeedKph == 11.60)
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

        #expect(parsed.flags == 0x09FE)
        #expect(parsed.instantaneousSpeedKph == 11.67)
        #expect(parsed.instantaneousPowerWatts == 16)
        #expect(parsed.instantaneousCadenceRpm == 20)
        #expect(parsed.totalDistanceMeters == 0)
    }

    @Test func ftmsIndoorBikeData_parsesICBikeLogFrames_flags0244() async throws {
        // From provided log: FTMS Indoor Bike Data (2AD2) frames like:
        // 44 02 [speed u16 LE] [cadence u16 LE] [power s16 LE] [hr u8]
        // flags 0x0244 => instantaneous cadence (bit2), instantaneous power (bit6), heart rate (bit9)

        do {
            let payload = dataFromHex("4402240e7c00d10000")
            let parsed = SensorDataParser.parseFTMS(payload)
            #expect(parsed.flags == 0x0244)
            #expect(parsed.instantaneousSpeedKph == 36.20) // 0x0E24 / 100
            #expect(parsed.instantaneousCadenceRpm == 62)   // 0x007C / 2
            #expect(parsed.instantaneousPowerWatts == 209)  // 0x00D1
            #expect(parsed.heartRateBpm == 0)
        }

        do {
            let payload = dataFromHex("4402de0d7c00cc0000")
            let parsed = SensorDataParser.parseFTMS(payload)
            #expect(parsed.flags == 0x0244)
            #expect(parsed.instantaneousSpeedKph == 35.50) // 0x0DDE / 100
            #expect(parsed.instantaneousCadenceRpm == 62)  // 0x007C / 2
            #expect(parsed.instantaneousPowerWatts == 204) // 0x00CC
            #expect(parsed.heartRateBpm == 0)
        }

        do {
            let payload = dataFromHex("4402b40f9e001d0100")
            let parsed = SensorDataParser.parseFTMS(payload)
            #expect(parsed.flags == 0x0244)
            #expect(parsed.instantaneousSpeedKph == 40.20) // 0x0FB4 / 100
            #expect(parsed.instantaneousCadenceRpm == 79)  // 0x009E / 2
            #expect(parsed.instantaneousPowerWatts == 285) // 0x011D
            #expect(parsed.heartRateBpm == 0)
        }
    }

    @Test func distanceEstimator_integratesSpeedOverTime() async throws {
        var est = DistanceEstimator()
        let t0 = Date(timeIntervalSince1970: 0)
        let t1 = Date(timeIntervalSince1970: 1)
        let t2 = Date(timeIntervalSince1970: 2)

        // First update has no prior point -> no delta.
        #expect(est.update(speedMps: 10, now: t0) == nil)

        // 10 m/s for 1 second -> 10 meters.
        let s1 = est.update(speedMps: 10, now: t1)
        #expect(s1?.deltaMeters == 10)
        #expect(s1?.start == t0)
        #expect(s1?.end == t1)

        // 8 m/s for 1 second -> 8 meters.
        let s2 = est.update(speedMps: 8, now: t2)
        #expect(s2?.deltaMeters == 8)
        #expect(s2?.start == t1)
        #expect(s2?.end == t2)
    }

    @Test func distanceEstimator_skipsVeryDelayedUpdates() async throws {
        var est = DistanceEstimator()
        let t0 = Date(timeIntervalSince1970: 0)
        let t10 = Date(timeIntervalSince1970: 10)
        let t11 = Date(timeIntervalSince1970: 11)

        #expect(est.update(speedMps: 10, now: t0) == nil)
        // 10s gap is too large (dt > 5) -> skip to avoid a huge jump.
        #expect(est.update(speedMps: 10, now: t10) == nil)
        // Now 1s later it should resume normally.
        let s = est.update(speedMps: 10, now: t11)
        #expect(s?.deltaMeters == 10)
    }

}
