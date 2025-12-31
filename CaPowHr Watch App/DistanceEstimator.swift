import Foundation

/// Pure helper to estimate cumulative distance by integrating instantaneous speed over time.
///
/// This exists because some FTMS bikes do not include the "Total Distance" optional field
/// in Indoor Bike Data (0x2AD2). In that case we still want a plausible distance readout.
struct DistanceEstimator {
    private(set) var lastUpdate: Date?

    mutating func reset() {
        lastUpdate = nil
    }

    /// Updates the estimator with the latest speed value.
    ///
    /// - Parameters:
    ///   - speedMps: Instantaneous speed in meters/second.
    ///   - now: The timestamp when this speed sample was observed.
    /// - Returns: A delta distance sample to apply, including the time window, or nil if no delta can be computed yet.
    mutating func update(speedMps: Double, now: Date) -> (deltaMeters: Double, start: Date, end: Date)? {
        guard speedMps.isFinite, speedMps >= 0 else {
            lastUpdate = now
            return nil
        }

        guard let start = lastUpdate else {
            lastUpdate = now
            return nil
        }

        let dt = now.timeIntervalSince(start)
        // Guard against clock issues or very delayed updates (e.g. paused background).
        guard dt > 0, dt <= 5 else {
            lastUpdate = now
            return nil
        }

        let delta = speedMps * dt
        lastUpdate = now
        return (deltaMeters: delta, start: start, end: now)
    }
}


