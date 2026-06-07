import Foundation

struct WorkoutSummaryData {
    let workoutType: WorkoutType
    let durationSeconds: TimeInterval
    let distanceMeters: Double
    let averageHeartRate: Double?
    let averagePower: Double?
    let averageCadence: Double?
    let laps: [LapRecord]
    let isDisplayOnlyMode: Bool
    let startDate: Date

    var uploadData: WorkoutUploadData {
        WorkoutUploadData(
            workoutType: workoutType,
            startDate: startDate,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            averageHeartRate: averageHeartRate,
            averagePower: averagePower,
            averageCadence: averageCadence
        )
    }
}

final class WorkoutStatsTracker {
    private var heartRateSamples: [Double] = []
    private var powerSamples: [Double] = []
    private var cadenceSamples: [Double] = []
    private(set) var laps: [LapRecord] = []
    private var lapStartDate: Date?
    private var lapStartDistanceMeters: Double = 0
    private var workoutStartDate: Date?

    func begin(at date: Date = Date()) {
        reset()
        workoutStartDate = date
        lapStartDate = date
        lapStartDistanceMeters = 0
    }

    func reset() {
        heartRateSamples.removeAll()
        powerSamples.removeAll()
        cadenceSamples.removeAll()
        laps.removeAll()
        lapStartDate = nil
        lapStartDistanceMeters = 0
        workoutStartDate = nil
    }

    func recordHeartRate(_ bpm: Double) {
        guard bpm > 0 else { return }
        heartRateSamples.append(bpm)
    }

    func recordPower(_ watts: Double) {
        guard watts > 0 else { return }
        powerSamples.append(watts)
    }

    func recordCadence(_ rpm: Double) {
        guard rpm > 0 else { return }
        cadenceSamples.append(rpm)
    }

    @discardableResult
    func recordLap(at date: Date = Date(), totalDistanceMeters: Double, durationSeconds: TimeInterval) -> LapRecord {
        let lapDuration = max(0, date.timeIntervalSince(lapStartDate ?? date))
        let lapDistance = max(0, totalDistanceMeters - lapStartDistanceMeters)
        let lap = LapRecord(
            number: laps.count + 1,
            durationSeconds: lapDuration,
            distanceMeters: lapDistance,
            recordedAt: date
        )
        laps.append(lap)
        lapStartDate = date
        lapStartDistanceMeters = totalDistanceMeters
        return lap
    }

    func makeSummary(
        workoutType: WorkoutType,
        durationSeconds: TimeInterval,
        distanceMeters: Double,
        isDisplayOnlyMode: Bool
    ) -> WorkoutSummaryData {
        WorkoutSummaryData(
            workoutType: workoutType,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            averageHeartRate: average(of: heartRateSamples),
            averagePower: average(of: powerSamples),
            averageCadence: average(of: cadenceSamples),
            laps: laps,
            isDisplayOnlyMode: isDisplayOnlyMode,
            startDate: workoutStartDate ?? Date().addingTimeInterval(-durationSeconds)
        )
    }

    private func average(of samples: [Double]) -> Double? {
        guard !samples.isEmpty else { return nil }
        return samples.reduce(0, +) / Double(samples.count)
    }
}

struct LapRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let number: Int
    let durationSeconds: TimeInterval
    let distanceMeters: Double
    let recordedAt: Date

    init(id: UUID = UUID(), number: Int, durationSeconds: TimeInterval, distanceMeters: Double, recordedAt: Date) {
        self.id = id
        self.number = number
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.recordedAt = recordedAt
    }
}
