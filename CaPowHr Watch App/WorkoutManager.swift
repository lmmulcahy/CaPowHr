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
    
    // MARK: - Health Services
    private let hkManager = HealthKitManager()
    
    // MARK: - CoreBluetooth Properties
    private var centralManager: CBCentralManager!
    private let bluetoothManager = BluetoothManager()
    // BLE fields moved into BluetoothManager
    
    // MARK: - Workout Timer
    private let workoutTimer = WorkoutTimer()
    
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
    func requestHealthKitAuthorization() { hkManager.requestAuthorization() }
    
    // MARK: - Workout Control
    func startWorkout() {
        guard !isWorkoutActive else { return }
        
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .cycling
        configuration.locationType = .indoor
        
        hkManager.beginWorkout { [weak self] success, error in
            if let error = error {
                print("Error beginning workout collection: \(error.localizedDescription)")
            } else if success {
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.isWorkoutActive = true
                    self.hkManager.delegate = self
                    self.hkManager.startHeartRateQuery()
                    self.workoutTimer.onTick = { [weak self] seconds in self?.workoutDuration = seconds }
                    self.workoutTimer.start()
                    self.startScanning()
                    self.lastEnergyUpdateTime = Date()
                    self.lastDistanceUpdateTime = Date()
                    self.lastDistanceMetersSaved = 0
                }
            }
        }
    }
    
    func stopWorkout() {
        guard isWorkoutActive else { return }
        
        hkManager.endWorkoutCollection { success, error in
            if let error = error {
                print("Error ending workout collection: \(error.localizedDescription)")
            } else {
                // Transition to post-workout confirmation UI
                DispatchQueue.main.async {
                    self.isAwaitingSave = true
                    self.isWorkoutActive = false
                    self.workoutTimer.stop()
                    self.hkManager.stopHeartRateQuery()
                    self.stopScanning()
                }
            }
        }
    }
    
    private func finishWorkout() {
        hkManager.finishWorkout { [weak self] success, _ in
            if success { print("Workout saved successfully") }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isWorkoutActive = false
                self.isAwaitingSave = false
                self.workoutTimer.stop()
                self.hkManager.stopHeartRateQuery()
                self.disconnectAllPeripherals()
            }
        }
    }

    // MARK: - Post-workout actions
    func confirmSaveWorkout() {
        finishWorkout()
    }
    
    func discardCurrentWorkout() {
        hkManager.discardWorkout()
        print("Workout discarded")
        DispatchQueue.main.async {
            self.isAwaitingSave = false
            self.isWorkoutActive = false
            self.workoutTimer.stop()
            self.hkManager.stopHeartRateQuery()
            self.disconnectAllPeripherals()
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
    
    // Heart rate query handled by HealthKitManager
    
    // Workout timing handled by WorkoutTimer
    
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
    
    // Sample writes are delegated to HealthKitManager
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
        hkManager.addPowerSample(watts)
    }
    
    func btDidUpdateCadence(rpm: Double) {
        DispatchQueue.main.async { self.cyclingCadence = rpm }
        hkManager.addCadenceSample(rpm)
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
                hkManager.addDistanceSample(delta, start: lastTime, end: now)
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

// MARK: - HealthKitManagerDelegate
extension WorkoutManager: HealthKitManagerDelegate {
    func hkDidUpdateHeartRate(_ bpm: Double) {
        DispatchQueue.main.async { self.heartRate = bpm }
    }
}

// MARK: - CBPeripheralDelegate
// Peripheral delegate handled by BluetoothManager
