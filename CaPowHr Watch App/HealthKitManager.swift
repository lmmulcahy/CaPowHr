import Foundation
import HealthKit

protocol HealthKitManagerDelegate: AnyObject {
    func hkDidUpdateHeartRate(_ bpm: Double)
    /// Running total of the active energy Apple's data source has collected into
    /// the builder, in kcal. Only fires while `activeEnergyBurned` collection is
    /// still enabled.
    func hkDidUpdateActiveEnergy(_ kcal: Double)
    /// The workout session failed or ended without the app asking it to.
    func hkWorkoutSessionDidFail(_ message: String)
}

final class HealthKitManager: NSObject {
    weak var delegate: HealthKitManagerDelegate?

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKWorkoutBuilder?
    /// Retained so `activeEnergyBurned` collection can be turned off mid-session
    /// if the machine turns out to report its own energy.
    private var liveDataSource: HKLiveWorkoutDataSource?
    private var heartRateQuery: HKAnchoredObjectQuery?

    // MARK: - Write throttling (avoid spamming HealthKit at BLE notification rate)
    private var lastPowerWriteAt: Date?
    private var lastCadenceWriteAt: Date?
    private var lastHeartRateWriteAt: Date?
    private var lastSpeedWriteAt: Date?
    private let minWriteInterval: TimeInterval = 1.0

    // MARK: - Authorization
    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("HealthKit is not available on this device")
            return
        }

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!
        ]

        let typesToWrite: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .cyclingPower)!,
            HKObjectType.quantityType(forIdentifier: .cyclingCadence)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .distanceCycling)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .runningSpeed)!,
            HKObjectType.quantityType(forIdentifier: .walkingSpeed)!
        ]

        healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead) { success, error in
            if let error = error {
                print("HealthKit authorization error: \(error.localizedDescription)")
            } else if success {
                print("HealthKit authorization granted")
            }
        }
    }

    // MARK: - Workout Configuration
    func configuration(for workoutType: WorkoutType) -> HKWorkoutConfiguration {
        let config = HKWorkoutConfiguration()
        config.locationType = .indoor
        
        switch workoutType {
        case .indoorCycle:
            config.activityType = .cycling
        case .indoorRun:
            config.activityType = .running
        case .indoorWalk:
            config.activityType = .walking
        case .indoorRow:
            config.activityType = .rowing
        }
        
        return config
    }

    // MARK: - Authorization Status Helpers
    func isWorkoutSharingAuthorized() -> Bool {
        return healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    // MARK: - Workout lifecycle
    func beginWorkout(configuration: HKWorkoutConfiguration = {
        let c = HKWorkoutConfiguration()
        c.activityType = .cycling
        c.locationType = .indoor
        return c
    }(), completion: @escaping (Bool, Error?) -> Void) {
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            self.workoutSession = session
            self.workoutBuilder = builder
            // Assign a live data source to ensure metrics stream correctly on all watchOS versions
            let dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            // CaPowHr writes its own heart-rate and distance samples (equipment data,
            // honoring the user's HR-source preference). Disable automatic collection of
            // those types so the watch's own estimates don't sum with ours in the workout
            // totals (double-counted distance, duplicated HR).
            //
            // activeEnergyBurned is deliberately NOT in this list: Apple's estimate is
            // heart-rate informed and is what the Move ring shows live, so it owns energy
            // by default. Only a machine that demonstrably measures its own energy takes
            // over, via stopCollectingActiveEnergy().
            let selfWrittenTypes: [HKQuantityTypeIdentifier] = [
                .heartRate, .distanceCycling, .distanceWalkingRunning
            ]
            for identifier in selfWrittenTypes {
                if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                    dataSource.disableCollection(for: type)
                }
            }
            self.liveDataSource = dataSource
            builder.dataSource = dataSource
            builder.delegate = self
            session.delegate = self
            session.startActivity(with: Date())
            builder.beginCollection(withStart: Date()) { success, error in
                completion(success, error)
            }
        } catch {
            completion(false, error)
        }
    }

    /// Hand ownership of `activeEnergyBurned` to the caller, which will write the
    /// machine's own energy from here on. Energy Apple already collected stays in
    /// the builder; the caller must not re-book that interval.
    func stopCollectingActiveEnergy() {
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return }
        liveDataSource?.disableCollection(for: type)
    }

    func endWorkoutCollection(completion: @escaping (Bool, Error?) -> Void) {
        workoutSession?.end()
        workoutBuilder?.endCollection(withEnd: Date()) { success, error in
            completion(success, error)
        }
    }

    func pauseWorkout(at date: Date = Date()) {
        workoutSession?.pause()
    }

    func resumeWorkout(at date: Date = Date()) {
        workoutSession?.resume()
    }

    func finishWorkout(completion: @escaping (Bool, Error?) -> Void) {
        workoutBuilder?.finishWorkout { _, error in
            if let error = error {
                print("Error finishing workout: \(error.localizedDescription)")
                completion(false, error)
            } else {
                completion(true, nil)
            }
            self.workoutBuilder = nil
            self.workoutSession = nil
            self.liveDataSource = nil
        }
    }

    func discardWorkout() {
        workoutBuilder?.discardWorkout()
        workoutBuilder = nil
        workoutSession = nil
        liveDataSource = nil
    }

    // MARK: - Heart Rate
    func startHeartRateQuery() {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        let predicate = HKQuery.predicateForSamples(withStart: Date(), end: nil, options: .strictStartDate)

        heartRateQuery = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, error in
            guard error == nil, let samples = samples as? [HKQuantitySample], let latest = samples.last else { return }
            let bpm = latest.quantity.doubleValue(for: HKUnit(from: "count/min"))
            DispatchQueue.main.async { self?.delegate?.hkDidUpdateHeartRate(bpm) }
        }

        heartRateQuery?.updateHandler = { [weak self] _, samples, _, _, error in
            guard error == nil, let samples = samples as? [HKQuantitySample], let latest = samples.last else { return }
            let bpm = latest.quantity.doubleValue(for: HKUnit(from: "count/min"))
            DispatchQueue.main.async { self?.delegate?.hkDidUpdateHeartRate(bpm) }
        }

        if let query = heartRateQuery { healthStore.execute(query) }
    }

    func stopHeartRateQuery() {
        if let query = heartRateQuery { healthStore.stop(query) }
        heartRateQuery = nil
    }

    // MARK: - Sample writes
    func addPowerSample(_ power: Double) {
        let now = Date()
        if let last = lastPowerWriteAt, now.timeIntervalSince(last) < minWriteInterval { return }
        lastPowerWriteAt = now
        guard let type = HKQuantityType.quantityType(forIdentifier: .cyclingPower) else { return }
        let quantity = HKQuantity(unit: HKUnit.watt(), doubleValue: power)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: now, end: now)
        workoutBuilder?.add([sample]) { success, error in
            if let error = error { print("Error adding power sample: \(error.localizedDescription)") }
        }
    }

    func addCadenceSample(_ cadenceRpm: Double) {
        let now = Date()
        if let last = lastCadenceWriteAt, now.timeIntervalSince(last) < minWriteInterval { return }
        lastCadenceWriteAt = now
        guard let type = HKQuantityType.quantityType(forIdentifier: .cyclingCadence) else { return }
        let quantity = HKQuantity(unit: HKUnit.count().unitDivided(by: HKUnit.minute()), doubleValue: cadenceRpm)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: now, end: now)
        workoutBuilder?.add([sample]) { _, error in
            if let error = error { print("Error adding cadence sample: \(error.localizedDescription)") }
        }
    }

    func addDistanceSample(_ distanceMetersDelta: Double, start: Date, end: Date) {
        guard let type = HKQuantityType.quantityType(forIdentifier: .distanceCycling) else { return }
        let quantity = HKQuantity(unit: HKUnit.meter(), doubleValue: distanceMetersDelta)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: start, end: end)
        workoutBuilder?.add([sample]) { _, error in
            if let error = error { print("Error adding distance sample: \(error.localizedDescription)") }
        }
    }

    func addWalkingRunningDistanceSample(_ distanceMetersDelta: Double, start: Date, end: Date) {
        guard let type = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) else { return }
        let quantity = HKQuantity(unit: HKUnit.meter(), doubleValue: distanceMetersDelta)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: start, end: end)
        workoutBuilder?.add([sample]) { _, error in
            if let error = error { print("Error adding walking/running distance sample: \(error.localizedDescription)") }
        }
    }

    func addEnergyBurnedSample(_ kiloCalories: Double, start: Date, end: Date) {
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return }
        let quantity = HKQuantity(unit: HKUnit.kilocalorie(), doubleValue: kiloCalories)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: start, end: end)
        workoutBuilder?.add([sample]) { _, error in
            if let error = error { print("Error adding energy sample: \(error.localizedDescription)") }
        }
    }

    func addHeartRateSample(_ bpm: Double) {
        let now = Date()
        if let last = lastHeartRateWriteAt, now.timeIntervalSince(last) < minWriteInterval { return }
        lastHeartRateWriteAt = now
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        let quantity = HKQuantity(unit: HKUnit(from: "count/min"), doubleValue: bpm)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: now, end: now)
        workoutBuilder?.add([sample]) { _, error in
            if let error = error { print("Error adding heart rate sample: \(error.localizedDescription)") }
        }
    }

    func addSpeedSample(_ metersPerSecond: Double, isRunning: Bool) {
        let now = Date()
        if let last = lastSpeedWriteAt, now.timeIntervalSince(last) < minWriteInterval { return }
        lastSpeedWriteAt = now
        let identifier: HKQuantityTypeIdentifier = isRunning ? .runningSpeed : .walkingSpeed
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return }
        let quantity = HKQuantity(unit: HKUnit.meter().unitDivided(by: HKUnit.second()), doubleValue: metersPerSecond)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: now, end: now)
        workoutBuilder?.add([sample]) { _, error in
            if let error = error { print("Error adding speed sample: \(error.localizedDescription)") }
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate
extension HealthKitManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
              collectedTypes.contains(energyType),
              let sum = workoutBuilder.statistics(for: energyType)?.sumQuantity()
        else { return }

        let kcal = sum.doubleValue(for: HKUnit.kilocalorie())
        DispatchQueue.main.async { self.delegate?.hkDidUpdateActiveEnergy(kcal) }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Pause/resume/lap markers are driven from WorkoutManager; nothing to do here.
    }
}

// MARK: - HKWorkoutSessionDelegate
extension HealthKitManager: HKWorkoutSessionDelegate {
    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        print("Workout session state: \(fromState.rawValue) -> \(toState.rawValue)")
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("Workout session failed: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.delegate?.hkWorkoutSessionDidFail(error.localizedDescription)
        }
    }
}


