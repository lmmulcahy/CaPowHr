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
    @Published var isScanning: Bool = false
    @Published var connectedDevices: [String] = []
    
    // MARK: - HealthKit Properties
    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKWorkoutBuilder?
    private var heartRateQuery: HKAnchoredObjectQuery?
    
    // MARK: - CoreBluetooth Properties
    private var centralManager: CBCentralManager!
    private var connectedPeripherals: [CBPeripheral] = []
    private var powerCharacteristic: CBCharacteristic?
    private var cadenceCharacteristic: CBCharacteristic?
    
    // MARK: - Workout Timer
    private var workoutTimer: Timer?
    private var workoutStartTime: Date?
    
    // MARK: - Bluetooth Service and Characteristic UUIDs
    private let cyclingPowerServiceUUID = CBUUID(string: "1818")
    private let cyclingSpeedCadenceServiceUUID = CBUUID(string: "1816")
    private let powerMeasurementCharacteristicUUID = CBUUID(string: "2A63")
    private let cscMeasurementCharacteristicUUID = CBUUID(string: "2A5B")
    
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
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
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
                self.finishWorkout()
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
                self?.stopWorkoutTimer()
                self?.stopHeartRateQuery()
                self?.disconnectAllPeripherals()
            }
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
    private func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        
        isScanning = true
        centralManager.scanForPeripherals(withServices: [cyclingPowerServiceUUID, cyclingSpeedCadenceServiceUUID], options: nil)
    }
    
    private func stopScanning() {
        isScanning = false
        centralManager.stopScan()
    }
    
    private func disconnectAllPeripherals() {
        for peripheral in connectedPeripherals {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        connectedPeripherals.removeAll()
        connectedDevices.removeAll()
    }
    
    // MARK: - Data Parsing
    private func parsePowerData(_ data: Data) {
        guard data.count >= 2 else { return }
        
        let powerBytes = data.subdata(in: 0..<2)
        let power = powerBytes.withUnsafeBytes { $0.load(as: UInt16.self) }
        
        DispatchQueue.main.async {
            self.cyclingPower = Double(power)
        }
        
        // Add to HealthKit
        addPowerSample(Double(power))
    }
    
    private func parseCadenceData(_ data: Data) {
        guard data.count >= 6 else { return }
        
        let _ = data[0] // flags - not used in this implementation
        let crankRevolutionCount = data.subdata(in: 1..<3).withUnsafeBytes { $0.load(as: UInt16.self) }
        let lastCrankRevolutionTime = data.subdata(in: 3..<5).withUnsafeBytes { $0.load(as: UInt16.self) }
        
        // Calculate RPM
        if self.lastCrankRevolutionCount != 0 {
            let revolutionDelta = crankRevolutionCount - self.lastCrankRevolutionCount
            let timeDelta = lastCrankRevolutionTime - self.lastCrankRevolutionTime
            
            if timeDelta > 0 {
                let rpm = Double(revolutionDelta) * 1024.0 / Double(timeDelta) * 60.0
                
                DispatchQueue.main.async {
                    self.cyclingCadence = rpm
                }
                
                // Add to HealthKit
                addCadenceSample(rpm)
            }
        }
        
        self.lastCrankRevolutionCount = crankRevolutionCount
        self.lastCrankRevolutionTime = lastCrankRevolutionTime
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
        
        let cadenceQuantity = HKQuantity(unit: HKUnit(from: "rev/min"), doubleValue: cadence)
        let cadenceSample = HKQuantitySample(type: cadenceType, quantity: cadenceQuantity, start: Date(), end: Date())
        
        workoutBuilder?.add([cadenceSample]) { success, error in
            if let error = error {
                print("Error adding cadence sample: \(error.localizedDescription)")
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
        
        if !connectedPeripherals.contains(peripheral) {
            connectedPeripherals.append(peripheral)
            central.connect(peripheral, options: nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to peripheral: \(peripheral.name ?? "Unknown")")
        
        DispatchQueue.main.async {
            self.connectedDevices.append(peripheral.name ?? "Unknown Device")
        }
        
        peripheral.delegate = self
        peripheral.discoverServices([cyclingPowerServiceUUID, cyclingSpeedCadenceServiceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect to peripheral: \(error?.localizedDescription ?? "Unknown error")")
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected from peripheral: \(peripheral.name ?? "Unknown")")
        
        DispatchQueue.main.async {
            self.connectedDevices.removeAll { $0 == peripheral.name ?? "Unknown Device" }
        }
        
        if let index = connectedPeripherals.firstIndex(of: peripheral) {
            connectedPeripherals.remove(at: index)
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
            
            if characteristic.uuid == powerMeasurementCharacteristicUUID {
                powerCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            } else if characteristic.uuid == cscMeasurementCharacteristicUUID {
                cadenceCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        
        if characteristic.uuid == powerMeasurementCharacteristicUUID {
            parsePowerData(data)
        } else if characteristic.uuid == cscMeasurementCharacteristicUUID {
            parseCadenceData(data)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Error updating notification state: \(error.localizedDescription)")
        } else {
            print("Notification state updated for characteristic: \(characteristic.uuid)")
        }
    }
}
