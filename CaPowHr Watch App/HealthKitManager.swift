import Foundation
import HealthKit

protocol HealthKitManagerDelegate: AnyObject {
    func hkDidUpdateHeartRate(_ bpm: Double)
}

final class HealthKitManager: NSObject {
    weak var delegate: HealthKitManagerDelegate?

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKWorkoutBuilder?
    private var heartRateQuery: HKAnchoredObjectQuery?

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
            HKObjectType.quantityType(forIdentifier: .distanceCycling)!
        ]

        healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead) { success, error in
            if let error = error {
                print("HealthKit authorization error: \(error.localizedDescription)")
            } else if success {
                print("HealthKit authorization granted")
            }
        }
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
            session.startActivity(with: Date())
            builder.beginCollection(withStart: Date()) { success, error in
                completion(success, error)
            }
        } catch {
            completion(false, error)
        }
    }

    func endWorkoutCollection(completion: @escaping (Bool, Error?) -> Void) {
        workoutSession?.end()
        workoutBuilder?.endCollection(withEnd: Date()) { success, error in
            completion(success, error)
        }
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
        }
    }

    func discardWorkout() {
        workoutBuilder?.discardWorkout()
        workoutBuilder = nil
        workoutSession = nil
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
        guard let type = HKQuantityType.quantityType(forIdentifier: .cyclingPower) else { return }
        let quantity = HKQuantity(unit: HKUnit.watt(), doubleValue: power)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: Date(), end: Date())
        workoutBuilder?.add([sample]) { success, error in
            if let error = error { print("Error adding power sample: \(error.localizedDescription)") }
        }
    }

    func addCadenceSample(_ cadenceRpm: Double) {
        guard let type = HKQuantityType.quantityType(forIdentifier: .cyclingCadence) else { return }
        let quantity = HKQuantity(unit: HKUnit.count().unitDivided(by: HKUnit.minute()), doubleValue: cadenceRpm)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: Date(), end: Date())
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

    func addEnergyBurnedSample(_ kiloCalories: Double, start: Date, end: Date) {
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return }
        let quantity = HKQuantity(unit: HKUnit.kilocalorie(), doubleValue: kiloCalories)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: start, end: end)
        workoutBuilder?.add([sample]) { _, error in
            if let error = error { print("Error adding energy sample: \(error.localizedDescription)") }
        }
    }
}


