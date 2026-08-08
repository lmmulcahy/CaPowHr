import Foundation

/// Who is responsible for the `activeEnergyBurned` samples in the saved workout.
enum EnergySource {
    /// Apple's own estimate, collected by `HKLiveWorkoutDataSource`. This is
    /// heart-rate informed and is what the Move ring shows live, so it is the
    /// default and the fallback for machines that don't measure energy.
    case appleEstimate
    /// The machine's FTMS Expended Energy counter, written by CaPowHr.
    case machineReported
}

/// Decides who owns `activeEnergyBurned` for a workout, and turns FTMS Expended
/// Energy totals into kcal deltas once the machine has taken ownership.
///
/// A workout starts on `.appleEstimate`. Ownership moves to the machine only once
/// its counter is seen to actually *increment* — not merely to be present in the
/// packet. Some FTMS bridges pad the Expended Energy field with zeros, and taking
/// ownership on presence alone would save a zero-calorie workout.
///
/// The increment that triggers the handover is deliberately discarded: Apple's
/// estimate already covered that interval, so booking it too would double-count.
struct EnergyOwnership {
    /// What the caller should do with a machine total it just received.
    enum Outcome: Equatable {
        /// Nothing to record.
        case ignore
        /// Stop Apple's collection; the machine owns energy from here on.
        /// No kcal are booked for this packet.
        case takeOwnership
        /// Book this many kcal against HealthKit.
        case delta(kcal: Double)
    }

    private(set) var source: EnergySource = .appleEstimate
    private var lastMachineTotalKcal: Double?

    /// Feed in the machine's cumulative Expended Energy (kcal) from an FTMS packet.
    mutating func apply(machineTotalKcal total: Double) -> Outcome {
        defer { lastMachineTotalKcal = total }

        guard let last = lastMachineTotalKcal else {
            // First total we've seen: establish a baseline, book nothing.
            return .ignore
        }

        switch source {
        case .appleEstimate:
            // Wait for proof the counter is live before displacing Apple's estimate.
            guard total > last else { return .ignore }
            source = .machineReported
            return .takeOwnership

        case .machineReported:
            let delta = total - last
            // Guard against a device reset or a non-monotonic stream; the deferred
            // assignment re-baselines so we resume counting on the next packet.
            guard delta > 0 else { return .ignore }
            return .delta(kcal: delta)
        }
    }

    /// Drop the baseline so the next packet re-establishes it without booking a
    /// delta. Called on resume, so anything the machine counted during the pause
    /// isn't booked as a burst.
    mutating func rebaseline() {
        lastMachineTotalKcal = nil
    }

    /// Return to the start-of-workout state.
    mutating func reset() {
        source = .appleEstimate
        lastMachineTotalKcal = nil
    }
}
