//
//  CaPowHr_Watch_AppTests.swift
//  CaPowHr Watch AppTests
//
//  Created by Luke Mulcahy on 9/15/25.
//

import Testing
import Foundation
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
        let parsed = CyclingSensorParser.parseIndoorBikeData(payload)

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
        let parsed = CyclingSensorParser.parseIndoorBikeData(payload)

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
            let parsed = CyclingSensorParser.parseIndoorBikeData(payload)
            #expect(parsed.flags == 0x0244)
            #expect(parsed.instantaneousSpeedKph == 36.20) // 0x0E24 / 100
            #expect(parsed.instantaneousCadenceRpm == 62)   // 0x007C / 2
            #expect(parsed.instantaneousPowerWatts == 209)  // 0x00D1
            #expect(parsed.heartRateBpm == 0)
        }

        do {
            let payload = dataFromHex("4402de0d7c00cc0000")
            let parsed = CyclingSensorParser.parseIndoorBikeData(payload)
            #expect(parsed.flags == 0x0244)
            #expect(parsed.instantaneousSpeedKph == 35.50) // 0x0DDE / 100
            #expect(parsed.instantaneousCadenceRpm == 62)  // 0x007C / 2
            #expect(parsed.instantaneousPowerWatts == 204) // 0x00CC
            #expect(parsed.heartRateBpm == 0)
        }

        do {
            let payload = dataFromHex("4402b40f9e001d0100")
            let parsed = CyclingSensorParser.parseIndoorBikeData(payload)
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

    @Test func cscDistanceEstimator_calibratesCircumferenceFromFTMSSpeed_andComputesDistance() async throws {
        // CSC samples from provided log (2A5B):
        // 03 c0 2e 01 00 ca b0 48 3b be 8f
        // 03 c5 2e 01 00 e8 b4 49 3b 8d 93
        //
        // Flags=0x03 => wheel + crank present.
        // Wheel rev deltas: 0x12EC0 -> 0x12EC5 = +5
        // Wheel time deltas: 0xB0CA -> 0xB4E8 = 1054 ticks = 1.029296875 s
        //
        // FTMS speed near this period (from log): 36.20 kph = 10.055555... m/s
        let csc1 = dataFromHex("03c02e0100cab0483bbe8f")
        let csc2 = dataFromHex("03c52e0100e8b4493b8d93")
        let p1 = CyclingSensorParser.parseCSC(csc1)
        let p2 = CyclingSensorParser.parseCSC(csc2)
        #expect(p1.wheelRev != nil)
        #expect(p2.wheelRev != nil)

        var est = CSCDistanceEstimator()
        // Prime with first sample (no delta yet).
        _ = est.update(wheelRev: p1.wheelRev!, wheelTime: p1.wheelTime!, speedMpsForCalibration: nil)

        let speedMps = 36.20 / 3.6
        let delta = est.update(wheelRev: p2.wheelRev!, wheelTime: p2.wheelTime!, speedMpsForCalibration: speedMps)

        // Circumference should land around ~2.07m for this bike/log.
        if let c = est.circumferenceMetersEstimate {
            #expect(c > 1.5)
            #expect(c < 3.0)
        } else {
            #expect(false, "Expected circumference to be calibrated")
        }

        // Delta distance should roughly match speed * dt ~ 10.35m (allow small tolerance due to smoothing/clamp).
        if let d = delta {
            #expect(d > 8.0)
            #expect(d < 13.0)
        } else {
            #expect(false, "Expected a delta distance once calibrated")
        }
    }

    @Test func treadmillData_parsesSpeedAndIncline() async throws {
        // Treadmill data packet:
        // flags = 0x000C (bit 2: total distance, bit 3: incline+ramp) -> 0C 00
        // speed = 0x0320 = 800 = 8.00 km/h -> 20 03
        // total distance (UInt24) = 2000 meters = 0x0007D0 -> D0 07 00
        // incline (SInt16) = 50 = 5.0% = 0x0032 -> 32 00
        // ramp angle (SInt16) = 30 = 3.0° = 0x001E -> 1E 00
        let payload = dataFromHex("0C002003D007003200 1E00")
        let parsed = TreadmillSensorParser.parseTreadmillData(payload)

        #expect(parsed.flags == 0x000C)
        #expect(parsed.instantaneousSpeedKph == 8.00)
        #expect(parsed.totalDistanceMeters == 2000)
        #expect(parsed.inclinePercent == 5.0)
        #expect(parsed.rampAngleDegrees == 3.0)
    }

    @Test func treadmillData_parsesMinimalPacket() async throws {
        // Just flags and speed (no optional fields)
        // flags = 0x0000
        // speed = 0x0258 = 600 = 6.00 km/h
        let payload = dataFromHex("00005802")
        let parsed = TreadmillSensorParser.parseTreadmillData(payload)

        #expect(parsed.flags == 0x0000)
        #expect(parsed.instantaneousSpeedKph == 6.00)
        #expect(parsed.totalDistanceMeters == nil)
        #expect(parsed.inclinePercent == nil)
    }

    // MARK: - Rower Data Tests

    @Test func rowerData_parsesStrokeRateAndCount() async throws {
        // Rower data packet with stroke rate and count (bit 0 = 0 means present):
        // flags = 0x0000 (bit 0 = 0, so stroke rate/count present)
        // stroke rate = 0x3C = 60 -> 30 strokes/min (0.5 resolution)
        // stroke count = 0x0064 = 100 strokes
        let payload = dataFromHex("00003C6400")
        let parsed = RowerSensorParser.parseRowerData(payload)

        #expect(parsed.flags == 0x0000)
        #expect(parsed.strokeRatePerMinute == 30.0)
        #expect(parsed.strokeCount == 100)
    }

    @Test func rowerData_parsesDistanceAndPace() async throws {
        // Rower data packet with distance and pace:
        // flags = 0x000D (bits 2 and 3 set: distance + pace; bit 0 = 1 means no stroke data)
        //   - bit 0 = 1 (no stroke data)
        //   - bit 2 = 1 (total distance present)
        //   - bit 3 = 1 (instantaneous pace present)
        // total distance (UInt24) = 5000 meters = 0x001388 -> 88 13 00
        // instantaneous pace = 120 seconds per 500m = 0x0078 -> 78 00
        let payload = dataFromHex("0D00881300 7800")
        let parsed = RowerSensorParser.parseRowerData(payload)

        #expect(parsed.flags == 0x000D)
        #expect(parsed.strokeRatePerMinute == nil)  // bit 0 = 1 means no stroke data
        #expect(parsed.totalDistanceMeters == 5000)
        #expect(parsed.instantaneousPaceSeconds500m == 120)
    }

    @Test func rowerData_parsesWithPower() async throws {
        // Rower data with stroke rate, count, and power:
        // flags = 0x0020 (bit 5 = power; bit 0 = 0 = stroke data present)
        // stroke rate = 0x38 = 56 -> 28 strokes/min
        // stroke count = 0x00C8 = 200 strokes
        // instantaneous power = 0x0096 = 150 watts
        let payload = dataFromHex("200038C8009600")
        let parsed = RowerSensorParser.parseRowerData(payload)

        #expect(parsed.flags == 0x0020)
        #expect(parsed.strokeRatePerMinute == 28.0)
        #expect(parsed.strokeCount == 200)
        #expect(parsed.instantaneousPowerWatts == 150)
    }

}

