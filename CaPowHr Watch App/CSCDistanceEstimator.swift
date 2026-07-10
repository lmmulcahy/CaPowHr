import Foundation

/// Estimates distance from CSC "Wheel Revolution Data" (cumulative wheel revolutions + last event time).
///
/// CSC reports wheel revolutions but not wheel circumference. Many indoor bikes report a "virtual wheel".
/// To avoid assuming a fixed circumference, this estimator can self-calibrate using an independent
/// speed source (e.g. FTMS instantaneous speed).
///
/// - Wheel event time is in 1/1024s ticks and wraps at UInt16.
/// - Wheel revolutions is UInt32 and is assumed monotonic for the session.
struct CSCDistanceEstimator {
    private(set) var circumferenceMetersEstimate: Double?
    private var lastWheelRev: UInt32?
    private var lastWheelTime: UInt16?

    mutating func reset() {
        circumferenceMetersEstimate = nil
        lastWheelRev = nil
        lastWheelTime = nil
    }

    /// Clears wheel history while keeping the calibrated circumference.
    /// Call on workout resume so revolutions that happened during a pause
    /// aren't converted into a distance jump on the first new sample.
    mutating func rebaseline() {
        lastWheelRev = nil
        lastWheelTime = nil
    }

    /// Update from a CSC wheel sample.
    ///
    /// - Parameters:
    ///   - wheelRev: Cumulative wheel revolutions (UInt32).
    ///   - wheelTime: Last wheel event time (UInt16 ticks @ 1024Hz).
    ///   - speedMpsForCalibration: Optional speed (m/s) from another source, used to calibrate circumference.
    /// - Returns: Delta distance in meters for this update, or nil if not enough history or no circumference yet.
    mutating func update(
        wheelRev: UInt32,
        wheelTime: UInt16,
        speedMpsForCalibration: Double?
    ) -> Double? {
        guard let prevRev = lastWheelRev, let prevTime = lastWheelTime else {
            lastWheelRev = wheelRev
            lastWheelTime = wheelTime
            return nil
        }

        // Revolutions are cumulative. If device resets mid-session, ignore this update.
        guard wheelRev >= prevRev else {
            lastWheelRev = wheelRev
            lastWheelTime = wheelTime
            return nil
        }

        let deltaRev = Double(wheelRev - prevRev)
        let deltaTicks = UInt16(bitPattern: Int16(bitPattern: wheelTime) &- Int16(bitPattern: prevTime))
        let dt = Double(deltaTicks) / 1024.0

        lastWheelRev = wheelRev
        lastWheelTime = wheelTime

        guard deltaRev > 0, dt > 0 else { return nil }

        // Optional calibration step.
        if let v = speedMpsForCalibration, v.isFinite, v >= 0 {
            // circumference = v * dt / deltaRev
            let raw = (v * dt) / deltaRev
            let clamped = min(max(raw, 0.5), 5.0) // generous bounds; indoor "virtual wheel" still should be sane
            if let prev = circumferenceMetersEstimate {
                // Exponential moving average for stability.
                circumferenceMetersEstimate = (0.2 * clamped) + (0.8 * prev)
            } else {
                circumferenceMetersEstimate = clamped
            }
        }

        guard let c = circumferenceMetersEstimate else { return nil }
        return deltaRev * c
    }
}


