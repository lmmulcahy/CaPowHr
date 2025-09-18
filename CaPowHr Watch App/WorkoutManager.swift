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
    
    // MARK: - Data Parsing
    private func parsePowerData(_ data: Data) {
        guard data.count >= 2 else { 
            print("Power data too short: \(data.count) bytes")
            return 
        }
        
        let powerBytes = data.subdata(in: 0..<2)
        let power = powerBytes.withUnsafeBytes { $0.load(as: UInt16.self) }
        
        print("Parsed power: \(power) watts")
        
        DispatchQueue.main.async {
            self.cyclingPower = Double(power)
        }
        
        // Add to HealthKit
        addPowerSample(Double(power))
    }
    
    private func parseCadenceData(_ data: Data) {
        // Cycling Speed and Cadence (CSC) Measurement (0x2A5B)
        // Flags (1 byte):
        // bit 0: Wheel Revolution Data Present
        // bit 1: Crank Revolution Data Present
        guard data.count >= 1 else {
            print("Cadence data too short: \(data.count) bytes")
            return
        }

        let flags = data[0]
        var offset = 1

        // Skip wheel data if present (UInt32 wheel revs + UInt16 last wheel event time)
        if (flags & 0x01) != 0 {
            guard data.count >= offset + 6 else {
                print("CSC: Wheel data indicated but packet too short")
                return
            }
            let wheelRevs = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self) }
            let wheelTime = data.subdata(in: (offset + 4)..<(offset + 6)).withUnsafeBytes { $0.load(as: UInt16.self) }
            offset += 6
            print("CSC Wheel - Revs: \(wheelRevs), Time: \(wheelTime)")
        }

        // Parse crank data if present
        guard (flags & 0x02) != 0 else {
            print("CSC: Crank data not present")
            return
        }

        guard data.count >= offset + 4 else {
            print("CSC: Crank data indicated but packet too short")
            return
        }

        let crankRevolutionCount = data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: UInt16.self) }
        let lastCrankRevolutionTime = data.subdata(in: (offset + 2)..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt16.self) }

        print("CSC Crank - Count: \(crankRevolutionCount), Time: \(lastCrankRevolutionTime)")

        // Calculate RPM using wrap-safe deltas (time unit: 1/1024 s)
        if self.lastCrankRevolutionCount != 0 {
            let revolutionDelta = UInt16(bitPattern: Int16(bitPattern: crankRevolutionCount) &- Int16(bitPattern: self.lastCrankRevolutionCount))
            let timeDelta = UInt16(bitPattern: Int16(bitPattern: lastCrankRevolutionTime) &- Int16(bitPattern: self.lastCrankRevolutionTime))

            let timeDeltaInt = Int(timeDelta)
            print("CSC calculation - Revolution delta: \(revolutionDelta), Time delta (ticks): \(timeDeltaInt)")

            if timeDeltaInt > 0 {
                let seconds = Double(timeDeltaInt) / 1024.0
                let rpm = (Double(revolutionDelta) / seconds) * 60.0

                print("Calculated cadence: \(rpm) RPM")

                DispatchQueue.main.async {
                    self.cyclingCadence = rpm
                }

                addCadenceSample(rpm)
            } else {
                print("CSC: Time delta is 0, cannot calculate RPM")
            }
        } else {
            print("CSC: First reading, storing initial values")
        }

        self.lastCrankRevolutionCount = crankRevolutionCount
        self.lastCrankRevolutionTime = lastCrankRevolutionTime
    }
    
    private func parseFTMSData(_ data: Data) {
        // Fitness Machine Service - Indoor Bike Data (0x2AD2)
        // Flags are 16-bit, little-endian
        guard data.count >= 2 else {
            print("FTMS data too short: \(data.count) bytes")
            return
        }

        let flags = UInt16(data[0]) | (UInt16(data[1]) << 8)
        var offset = 2

        func readUInt16() -> UInt16? {
            guard data.count >= offset + 2 else { return nil }
            let v = data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: UInt16.self) }
            offset += 2
            return v
        }

        func readInt16() -> Int16? {
            guard data.count >= offset + 2 else { return nil }
            let v = data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: Int16.self) }
            offset += 2
            return v
        }

        func readUInt8() -> UInt8? {
            guard data.count > offset else { return nil }
            let v = data[offset]
            offset += 1
            return v
        }

        func readUInt24() -> UInt32? {
            guard data.count >= offset + 3 else { return nil }
            let b0 = UInt32(data[offset])
            let b1 = UInt32(data[offset + 1])
            let b2 = UInt32(data[offset + 2])
            offset += 3
            return b0 | (b1 << 8) | (b2 << 16)
        }

        print(String(format: "FTMS flags: 0x%04X", flags))

        // Bit mapping (common for Indoor Bike Data):
        // 0x0001: More Data (ignored)
        // 0x0002: Instantaneous Speed present (SFloat -> stored as UInt16 scale 0.01 m/s)
        // 0x0004: Average Speed present
        // 0x0008: Instantaneous Cadence present (UInt16 in 0.5 RPM)
        // 0x0010: Average Cadence present (UInt16 in 0.5 RPM)
        // 0x0020: Total Distance present (UInt24 in meters)
        // 0x0040: Resistance Level present (Int16)
        // 0x0080: Instantaneous Power present (Int16 in watts)
        // 0x0100: Average Power present (Int16)
        // 0x0200: Total Energy present (UInt16 in kJ?)
        // 0x0400: Energy Per Hour present (UInt16)
        // 0x0800: Energy Per Minute present (UInt8)
        // 0x1000: Heart Rate present (UInt8)
        // 0x2000: MET present (UInt8)
        // 0x4000: Elapsed Time present (UInt16 seconds)
        // 0x8000: Remaining Time present (UInt16 seconds)

        if (flags & 0x0002) != 0, let instSpeedRaw = readUInt16() {
            // Spec: scale 0.01 m/s
            let speedMps = Double(instSpeedRaw) / 100.0
            print(String(format: "FTMS instantaneous speed: %.2f m/s (raw: %d)", speedMps, instSpeedRaw))
            DispatchQueue.main.async { self.cyclingSpeedMps = speedMps }
        }
        if (flags & 0x0004) != 0 { _ = readUInt16() /* avg speed */ }

        if (flags & 0x0008) != 0, let cadenceHalfRpm = readUInt16() {
            let cadenceRpm = Double(cadenceHalfRpm) / 2.0
            print("FTMS instantaneous cadence: \(cadenceRpm) RPM (raw: \(cadenceHalfRpm))")
            DispatchQueue.main.async { self.cyclingCadence = cadenceRpm }
            addCadenceSample(cadenceRpm)
        }

        if (flags & 0x0010) != 0 { _ = readUInt16() /* avg cadence */ }
        if (flags & 0x0020) != 0, let totalDistance = readUInt24() {
            let meters = Double(totalDistance)
            DispatchQueue.main.async { self.distanceMeters = meters }
            let now = Date()
            if let lastTime = lastDistanceUpdateTime {
                let delta = meters - lastDistanceMetersSaved
                if delta > 0 {
                    addDistanceSample(delta, start: lastTime, end: now)
                    // Fallback instantaneous speed from distance delta/time
                    let dt = now.timeIntervalSince(lastTime)
                    if dt > 0 {
                        let speedMpsFallback = delta / dt
                        DispatchQueue.main.async { self.cyclingSpeedMps = speedMpsFallback }
                    }
                    lastDistanceMetersSaved = meters
                    lastDistanceUpdateTime = now
                }
            } else {
                lastDistanceUpdateTime = now
                lastDistanceMetersSaved = meters
            }
        }
        if (flags & 0x0040) != 0 { _ = readInt16() /* resistance level */ }

        if (flags & 0x0080) != 0, let instPower = readInt16() {
            let powerWatts = Int(instPower)
            print("FTMS instantaneous power: \(powerWatts) W")
            DispatchQueue.main.async { self.cyclingPower = Double(powerWatts) }
            addPowerSample(Double(powerWatts))
            // Calculate and store active energy burned increment
            let now = Date()
            if let last = lastEnergyUpdateTime, powerWatts > 0 {
                let seconds = now.timeIntervalSince(last)
                if seconds > 0 {
                    let kcal = (Double(powerWatts) * seconds) / 4184.0
                    addEnergyBurnedSample(kcal, start: last, end: now)
                }
            }
            lastEnergyUpdateTime = now
        }

        if (flags & 0x0100) != 0 { _ = readInt16() /* avg power */ }
        if (flags & 0x0200) != 0 { _ = readUInt16() /* total energy */ }
        if (flags & 0x0400) != 0 { _ = readUInt16() /* energy/hour */ }
        if (flags & 0x0800) != 0 { _ = readUInt8()  /* energy/min */ }

        if (flags & 0x1000) != 0 {
            _ = readUInt8() // Heart rate present; ignore to avoid conflicting with watch HR
        }

        if (flags & 0x2000) != 0 { _ = readUInt8()  /* MET */ }
        if (flags & 0x4000) != 0 { _ = readUInt16() /* elapsed time */ }
        if (flags & 0x8000) != 0 { _ = readUInt16() /* remaining time */ }

        if data.count > offset {
            let remainingData = data.subdata(in: offset..<data.count)
            print("FTMS remaining data: \(remainingData.map { String(format: "%02X", $0) }.joined(separator: " "))")
        }
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
