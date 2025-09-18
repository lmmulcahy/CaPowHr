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
    private var connectedPeripherals: [CBPeripheral] = []
    private var connectingPeripherals: [CBPeripheral] = [] // Keep strong references during connection attempts
    private var powerCharacteristic: CBCharacteristic?
    private var cadenceCharacteristic: CBCharacteristic?
    
    // MARK: - Workout Timer
    private var workoutTimer: Timer?
    private var workoutStartTime: Date?
    
    // MARK: - HealthKit accumulation state
    private var lastEnergyUpdateTime: Date?
    private var lastDistanceUpdateTime: Date?
    private var lastDistanceMetersSaved: Double = 0
    
    // MARK: - Bluetooth Service and Characteristic UUIDs
    // Standard Cycling Services
    private let cyclingPowerServiceUUID = CBUUID(string: "1818")
    private let cyclingSpeedCadenceServiceUUID = CBUUID(string: "1816")
    private let powerMeasurementCharacteristicUUID = CBUUID(string: "2A63")
    private let cscMeasurementCharacteristicUUID = CBUUID(string: "2A5B")
    
    // FTMS (Fitness Machine Service)
    private let ftmsServiceUUID = CBUUID(string: "1826")
    private let ftmsDataCharacteristicUUID = CBUUID(string: "2AD2")
    private let ftmsControlPointCharacteristicUUID = CBUUID(string: "2AD9")
    
    // MARK: - Cadence Calculation
    private var lastCrankRevolutionTime: UInt16 = 0
    private var lastCrankRevolutionCount: UInt16 = 0
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
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
        startScanning()
    }
    
    func disconnectSensors() {
        stopScanning()
        disconnectAllPeripherals()
    }
    
    private func startScanning() {
        // Avoid re-entrant scanning
        if isScanning { 
            print("Already scanning; ignoring startScanning request")
            return 
        }
        guard centralManager.state == .poweredOn else { 
            print("Bluetooth not powered on, state: \(centralManager.state.rawValue)")
            return 
        }
        
        isScanning = true
        print("Starting Bluetooth scan for cycling services...")
        
        // First scan for all devices to see what's available
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        
        // After 5 seconds, switch to specific service scanning
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            if self.isScanning {
                print("Switching to specific service scanning...")
                self.centralManager.stopScan()
                self.centralManager.scanForPeripherals(
                    withServices: [self.cyclingPowerServiceUUID, self.cyclingSpeedCadenceServiceUUID, self.ftmsServiceUUID],
                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
                )
            }
        }
    }
    
    private func stopScanning() {
        if !isScanning { return }
        isScanning = false
        print("Stopping Bluetooth scan...")
        centralManager.stopScan()
    }
    
    private func disconnectAllPeripherals() {
        // Cancel connections for both connected and connecting peripherals
        for peripheral in connectedPeripherals {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        for peripheral in connectingPeripherals {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        
        connectedPeripherals.removeAll()
        connectingPeripherals.removeAll()
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

        if (flags & 0x0002) != 0 { _ = readUInt16() /* inst speed */ }
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


// MARK: - CBCentralManagerDelegate
extension WorkoutManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Bluetooth is powered on")
        case .poweredOff:
            print("Bluetooth is powered off")
        case .resetting:
            print("Bluetooth is resetting")
        case .unauthorized:
            print("Bluetooth is unauthorized")
        case .unsupported:
            print("Bluetooth is unsupported")
        case .unknown:
            print("Bluetooth state is unknown")
        @unknown default:
            print("Unknown Bluetooth state")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print("Discovered peripheral: \(peripheral.name ?? "Unknown")")
        print("Advertisement data: \(advertisementData)")
        print("RSSI: \(RSSI)")
        
        // Check if this peripheral has cycling services
        if let serviceUUIDs = advertisementData["kCBAdvDataServiceUUIDs"] as? [CBUUID] {
            let hasCyclingServices = serviceUUIDs.contains { uuid in
                uuid == cyclingPowerServiceUUID || 
                uuid == cyclingSpeedCadenceServiceUUID || 
                uuid == ftmsServiceUUID
            }
            
            if hasCyclingServices {
                print("Found cycling device: \(peripheral.name ?? "Unknown") - attempting connection")
                if !connectedPeripherals.contains(peripheral) && !connectingPeripherals.contains(peripheral) {
                    // Stop scanning to avoid interference with connection
                    stopScanning()
                    // Keep strong reference during connection attempt
                    connectingPeripherals.append(peripheral)
                    print("Connecting to \(peripheral.name ?? "Unknown")...")
                    central.connect(peripheral, options: nil)
                    print("Peripheral state after connect call: \(peripheral.state.rawValue)")
                }
            } else {
                print("Skipping non-cycling device: \(peripheral.name ?? "Unknown")")
            }
        } else {
            print("No service UUIDs in advertisement data for: \(peripheral.name ?? "Unknown")")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to peripheral: \(peripheral.name ?? "Unknown")")
        // Stop scanning once connected
        stopScanning()
        
        // Connection succeeded; ensure arrays reflect connected state
        if let index = connectingPeripherals.firstIndex(of: peripheral) {
            connectingPeripherals.remove(at: index)
        }
        if !connectedPeripherals.contains(peripheral) {
            connectedPeripherals.append(peripheral)
        }
        
        DispatchQueue.main.async {
            let deviceName = peripheral.name ?? "Unknown Device"
            if !self.connectedDevices.contains(deviceName) {
                self.connectedDevices.append(deviceName)
            }
        }
        
        peripheral.delegate = self
        peripheral.discoverServices([cyclingPowerServiceUUID, cyclingSpeedCadenceServiceUUID, ftmsServiceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect to peripheral: \(error?.localizedDescription ?? "Unknown error")")
        // Resume scanning to find devices again
        startScanning()
        
        // Clean up from both arrays to allow re-attempts
        if let index = connectingPeripherals.firstIndex(of: peripheral) {
            connectingPeripherals.remove(at: index)
        }
        if let index = connectedPeripherals.firstIndex(of: peripheral) {
            connectedPeripherals.remove(at: index)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected from peripheral: \(peripheral.name ?? "Unknown")")
        // Resume scanning to allow reconnection
        startScanning()
        
        DispatchQueue.main.async {
            self.connectedDevices.removeAll { $0 == peripheral.name ?? "Unknown Device" }
        }
        
        if let index = connectedPeripherals.firstIndex(of: peripheral) {
            connectedPeripherals.remove(at: index)
        }
        if let index = connectingPeripherals.firstIndex(of: peripheral) {
            connectingPeripherals.remove(at: index)
        }
    }
}

// MARK: - CBPeripheralDelegate
extension WorkoutManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        
        for service in services {
            print("Discovered service: \(service.uuid)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            print("Discovered characteristic: \(characteristic.uuid)")
            
            // Standard cycling services
            if characteristic.uuid == powerMeasurementCharacteristicUUID {
                powerCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            } else if characteristic.uuid == cscMeasurementCharacteristicUUID {
                cadenceCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
            // FTMS service
            else if characteristic.uuid == ftmsDataCharacteristicUUID {
                // FTMS data characteristic can provide both power and cadence
                powerCharacteristic = characteristic
                cadenceCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
            // Check for other power-related characteristics
            else if characteristic.uuid.uuidString == "2AD9" {
                // FTMS Power Range characteristic
                print("Found FTMS Power Range characteristic")
                peripheral.setNotifyValue(true, for: characteristic)
            } else if characteristic.uuid.uuidString == "2ADA" {
                // FTMS Resistance Level characteristic
                print("Found FTMS Resistance Level characteristic")
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { 
            print("No data received from characteristic: \(characteristic.uuid)")
            return 
        }
        
        print("Received data from characteristic: \(characteristic.uuid)")
        print("Data length: \(data.count) bytes")
        print("Data: \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
        
        if characteristic.uuid == powerMeasurementCharacteristicUUID {
            print("Parsing as cycling power data")
            parsePowerData(data)
        } else if characteristic.uuid == cscMeasurementCharacteristicUUID {
            print("Parsing as cycling cadence data")
            parseCadenceData(data)
        } else if characteristic.uuid == ftmsDataCharacteristicUUID {
            print("Parsing as FTMS data")
            parseFTMSData(data)
        } else {
            print("Unknown characteristic UUID: \(characteristic.uuid)")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Error updating notification state: \(error.localizedDescription)")
        } else {
            print("Notification state updated for characteristic: \(characteristic.uuid)")
            print("Characteristic properties: \(characteristic.properties.rawValue)")
            print("Characteristic isNotifying: \(characteristic.isNotifying)")
        }
    }
}
