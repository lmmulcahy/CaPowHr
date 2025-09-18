//
//  WorkoutManager.swift
//  CaPowHr Watch App
//
//  Created by Luke Mulcahy on 9/15/25.
//

import Foundation
import HealthKit
import CoreBluetooth
import WatchKit

class WorkoutManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var heartRate: Double = 0
    @Published var cyclingPower: Double = 0
    @Published var cyclingCadence: Double = 0
    @Published var cyclingSpeedMps: Double = 0
    @Published var workoutDuration: TimeInterval = 0
    @Published var isWorkoutActive: Bool = false
    @Published var isAwaitingSave: Bool = false
    @Published var isScanning: Bool = false
    @Published var connectedDevices: [String] = []
    @Published var distanceMeters: Double = 0
    
    // MARK: - HealthKit Properties
    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKWorkoutBuilder?
    private var heartRateQuery: HKAnchoredObjectQuery?
    
    // MARK: - CoreBluetooth Properties
    private var centralManager: CBCentralManager!
    private let bluetoothManager = BluetoothManager()
    // BLE fields moved into BluetoothManager
    
    // MARK: - Workout Timer
    private var workoutTimer: Timer?
    private var workoutStartTime: Date?
    
    // MARK: - HealthKit accumulation state
    private var lastEnergyUpdateTime: Date?
    private var lastDistanceUpdateTime: Date?
    private var lastDistanceMetersSaved: Double = 0
    
    // MARK: - Bluetooth Service and Characteristic UUIDs
    // Standard Cycling Services
    // UUIDs handled by BluetoothManager
    
    // MARK: - Cadence Calculation
    private var lastCrankRevolutionTime: UInt16 = 0
    private var lastCrankRevolutionCount: UInt16 = 0
    
    override init() {
        super.init()
        // Legacy central remains for backwards compatibility (will be removed)
        centralManager = CBCentralManager(delegate: self, queue: nil)
        bluetoothManager.delegate = self
    }
    
    // MARK: - HealthKit Authorization
    func requestHealthKitAuthorization() {
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
    
    // MARK: - Workout Control
    func startWorkout() {
        guard !isWorkoutActive else { return }
        
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .cycling
        configuration.locationType = .indoor
        
        do {
            workoutSession = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            workoutBuilder = workoutSession?.associatedWorkoutBuilder()
            
            workoutSession?.delegate = self
            
            workoutStartTime = Date()
            workoutSession?.startActivity(with: Date())
            workoutBuilder?.beginCollection(withStart: Date()) { [weak self] success, error in
                if let error = error {
                    print("Error beginning workout collection: \(error.localizedDescription)")
                } else {
                    DispatchQueue.main.async {
                        self?.isWorkoutActive = true
                        self?.startHeartRateQuery()
                        self?.startWorkoutTimer()
                        self?.startScanning()
                        // Initialize accumulation timestamps
                        self?.lastEnergyUpdateTime = Date()
                        self?.lastDistanceUpdateTime = Date()
                        self?.lastDistanceMetersSaved = 0
                    }
                }
            }
        } catch {
            print("Error starting workout: \(error.localizedDescription)")
        }
    }
    
    func stopWorkout() {
        guard isWorkoutActive else { return }
        
        workoutSession?.end()
        workoutBuilder?.endCollection(withEnd: Date()) { success, error in
            if let error = error {
                print("Error ending workout collection: \(error.localizedDescription)")
            } else {
                // Transition to post-workout confirmation UI
                DispatchQueue.main.async {
                    self.isAwaitingSave = true
                    self.isWorkoutActive = false
                    self.stopWorkoutTimer()
                    self.stopHeartRateQuery()
                    self.stopScanning()
                }
            }
        }
    }
    
    private func finishWorkout() {
        workoutBuilder?.finishWorkout { [weak self] workout, error in
            if let error = error {
                print("Error finishing workout: \(error.localizedDescription)")
            } else {
                print("Workout saved successfully")
            }
            
            DispatchQueue.main.async {
                self?.isWorkoutActive = false
                self?.isAwaitingSave = false
                self?.stopWorkoutTimer()
                self?.stopHeartRateQuery()
                self?.disconnectAllPeripherals()
                self?.workoutBuilder = nil
                self?.workoutSession = nil
            }
        }
    }

    // MARK: - Post-workout actions
    func confirmSaveWorkout() {
        finishWorkout()
    }
    
    func discardCurrentWorkout() {
        workoutBuilder?.discardWorkout()
        print("Workout discarded")
        DispatchQueue.main.async {
            self.isAwaitingSave = false
            self.isWorkoutActive = false
            self.stopWorkoutTimer()
            self.stopHeartRateQuery()
            self.disconnectAllPeripherals()
            self.workoutBuilder = nil
            self.workoutSession = nil
            // Reset metrics
            self.heartRate = 0
            self.cyclingPower = 0
            self.cyclingCadence = 0
            self.workoutDuration = 0
            self.lastEnergyUpdateTime = nil
            self.lastDistanceUpdateTime = nil
            self.lastDistanceMetersSaved = 0
        }
    }
    
    // MARK: - Heart Rate Monitoring
    private func startHeartRateQuery() {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        
        let predicate = HKQuery.predicateForSamples(withStart: Date(), end: nil, options: .strictStartDate)
        
        heartRateQuery = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] query, samples, deletedObjects, anchor, error in
            if let error = error {
                print("Heart rate query error: \(error.localizedDescription)")
                return
            }
            
            guard let samples = samples as? [HKQuantitySample] else { return }
            
            if let latestSample = samples.last {
                let heartRate = latestSample.quantity.doubleValue(for: HKUnit(from: "count/min"))
                DispatchQueue.main.async {
                    self?.heartRate = heartRate
                }
            }
        }
        
        heartRateQuery?.updateHandler = { [weak self] query, samples, deletedObjects, anchor, error in
            if let error = error {
                print("Heart rate query update error: \(error.localizedDescription)")
                return
            }
            
            guard let samples = samples as? [HKQuantitySample] else { return }
            
            if let latestSample = samples.last {
                let heartRate = latestSample.quantity.doubleValue(for: HKUnit(from: "count/min"))
                DispatchQueue.main.async {
                    self?.heartRate = heartRate
                }
            }
        }
        
        healthStore.execute(heartRateQuery!)
    }
    
    private func stopHeartRateQuery() {
        if let query = heartRateQuery {
            healthStore.stop(query)
            heartRateQuery = nil
        }
    }
    
    // MARK: - Workout Timer
    private func startWorkoutTimer() {
        workoutTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let startTime = self?.workoutStartTime else { return }
            DispatchQueue.main.async {
                self?.workoutDuration = Date().timeIntervalSince(startTime)
            }
        }
    }
    
    private func stopWorkoutTimer() {
        workoutTimer?.invalidate()
        workoutTimer = nil
        workoutDuration = 0
    }
    
    // MARK: - Bluetooth Scanning
    func startScanningForTesting() {
        bluetoothManager.startScanning()
    }
    
    func disconnectSensors() {
        bluetoothManager.stopScanning()
        bluetoothManager.disconnectAll()
    }
    
    private func startScanning() {
        // Avoid re-entrant scanning
        if isScanning { return }
        isScanning = true
        bluetoothManager.startScanning()
    }
    
    private func stopScanning() {
        if !isScanning { return }
        isScanning = false
        bluetoothManager.stopScanning()
    }
    
    private func disconnectAllPeripherals() {
        // Delegated to BluetoothManager
        bluetoothManager.disconnectAll()
        connectedDevices.removeAll()
    }
    
    // MARK: - HealthKit Sample Addition
    private func addPowerSample(_ power: Double) {
        guard let powerType = HKQuantityType.quantityType(forIdentifier: .cyclingPower) else { return }
        
        let powerQuantity = HKQuantity(unit: HKUnit.watt(), doubleValue: power)
        let powerSample = HKQuantitySample(type: powerType, quantity: powerQuantity, start: Date(), end: Date())
        
        workoutBuilder?.add([powerSample]) { success, error in
            if let error = error {
                print("Error adding power sample: \(error.localizedDescription)")
            }
        }
    }
    
    private func addCadenceSample(_ cadence: Double) {
        guard let cadenceType = HKQuantityType.quantityType(forIdentifier: .cyclingCadence) else { return }
        
        let cadenceQuantity = HKQuantity(unit: HKUnit.count().unitDivided(by: HKUnit.minute()), doubleValue: cadence)
        let cadenceSample = HKQuantitySample(type: cadenceType, quantity: cadenceQuantity, start: Date(), end: Date())
        
        workoutBuilder?.add([cadenceSample]) { success, error in
            if let error = error {
                print("Error adding cadence sample: \(error.localizedDescription)")
            }
        }
    }

    private func addDistanceSample(_ distanceMetersDelta: Double, start: Date, end: Date) {
        guard let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceCycling) else { return }
        let quantity = HKQuantity(unit: HKUnit.meter(), doubleValue: distanceMetersDelta)
        let sample = HKQuantitySample(type: distanceType, quantity: quantity, start: start, end: end)
        workoutBuilder?.add([sample]) { success, error in
            if let error = error {
                print("Error adding distance sample: \(error.localizedDescription)")
            }
        }
    }

    private func addEnergyBurnedSample(_ kiloCalories: Double, start: Date, end: Date) {
        guard let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return }
        let quantity = HKQuantity(unit: HKUnit.kilocalorie(), doubleValue: kiloCalories)
        let sample = HKQuantitySample(type: energyType, quantity: quantity, start: start, end: end)
        workoutBuilder?.add([sample]) { success, error in
            if let error = error {
                print("Error adding energy sample: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - HKWorkoutSessionDelegate
extension WorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        // Handle workout session state changes
    }
    
    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("Workout session failed: \(error.localizedDescription)")
    }
}


// MARK: - CBCentralManagerDelegate (legacy)
extension WorkoutManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // Delegate handled by BluetoothManager
        if central.state == .poweredOn {
            print("Bluetooth is powered on")
        }
    }
    
    // Remaining CBCentralManager delegate methods are handled by BluetoothManager
}

// MARK: - BluetoothManagerDelegate
extension WorkoutManager: BluetoothManagerDelegate {
    func btDidDiscoverCyclingDevice(name: String) {
        print("Found cycling device: \(name)")
    }
    
    func btDidConnect(to name: String) {
        DispatchQueue.main.async {
            if !self.connectedDevices.contains(name) { self.connectedDevices.append(name) }
            self.isScanning = false
        }
    }
    
    func btDidFailToConnect(name: String, error: Error?) {
        print("Failed to connect to: \(name) error: \(error?.localizedDescription ?? "unknown")")
        DispatchQueue.main.async { self.isScanning = true }
    }
    
    func btDidDisconnect(name: String, error: Error?) {
        DispatchQueue.main.async {
            self.connectedDevices.removeAll { $0 == name }
            self.isScanning = true
        }
    }
    
    func btDidUpdatePower(watts: Double) {
        DispatchQueue.main.async { self.cyclingPower = watts }
        addPowerSample(watts)
    }
    
    func btDidUpdateCadence(rpm: Double) {
        DispatchQueue.main.async { self.cyclingCadence = rpm }
        addCadenceSample(rpm)
    }
    
    func btDidUpdateSpeed(mps: Double) {
        DispatchQueue.main.async { self.cyclingSpeedMps = mps }
    }
    
    func btDidUpdateTotalDistance(meters: Double) {
        DispatchQueue.main.async { self.distanceMeters = meters }
        let now = Date()
        if let lastTime = lastDistanceUpdateTime {
            let delta = meters - lastDistanceMetersSaved
            if delta > 0 {
                addDistanceSample(delta, start: lastTime, end: now)
                let dt = now.timeIntervalSince(lastTime)
                if dt > 0 { DispatchQueue.main.async { self.cyclingSpeedMps = delta / dt } }
                lastDistanceMetersSaved = meters
                lastDistanceUpdateTime = now
            }
        } else {
            lastDistanceUpdateTime = now
            lastDistanceMetersSaved = meters
        }
    }
    
    func btDidUpdateConnectedDevices(_ names: [String]) {
        DispatchQueue.main.async { self.connectedDevices = names }
    }
}

// MARK: - CBPeripheralDelegate
// Peripheral delegate handled by BluetoothManager
