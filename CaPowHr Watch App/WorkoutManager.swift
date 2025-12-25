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
    @Published var isEndingCollection: Bool = false
    @Published var isScanning: Bool = false
    @Published var connectedDevices: [String] = []
    @Published var distanceMeters: Double = 0
    @Published var isDisplayOnlyMode: Bool = false
    @Published var lastErrorMessage: String? = nil
    @Published var showingErrorAlert: Bool = false
    @Published var alertTitle: String? = nil
    @Published var pendingDisplayOnlyStart: Bool = false
    
    // MARK: - Health Services
    private let hkManager = HealthKitManager()
    
    // MARK: - CoreBluetooth Properties
    private var centralManager: CBCentralManager!
    private let bluetoothManager = BluetoothManager()
    // BLE fields moved into BluetoothManager
    
    // MARK: - Workout Timer
    private let workoutTimer = WorkoutTimer()

    // MARK: - BLE Logging
    private let bleLog = BluetoothLogManager.shared
    
    // MARK: - HealthKit accumulation state
    private var lastEnergyUpdateTime: Date?
    private var lastDistanceUpdateTime: Date?
    private var lastDistanceMetersSaved: Double = 0
    private var hasSeenFTMSEnergy: Bool = false
    private var lastFTMSTotalEnergyKcal: Double?
    private var prefersBikeHeartRate: Bool = false
    private var lastBikeHeartRateAt: Date?
    
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

        let canShareWorkout = hkManager.isWorkoutSharingAuthorized()
        if !canShareWorkout {
            // Warn first; start display-only after user dismisses the alert
            DispatchQueue.main.async {
                self.alertTitle = "Limited Permissions"
                self.lastErrorMessage = "Workout will not be saved to Health because write permission is disabled. You can proceed to view live data, or enable workout write permissions for CaPowHr in the iPhone Health app."
                self.pendingDisplayOnlyStart = true
                self.showingErrorAlert = true
            }
            return
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .cycling
        configuration.locationType = .indoor
        
        hkManager.beginWorkout(configuration: configuration) { [weak self] success, error in
            if let error = error {
                print("Error beginning workout collection: \(error.localizedDescription)")
                // Fallback to display-only mode after user dismisses alert
                DispatchQueue.main.async {
                    self?.alertTitle = "Limited Functionality"
                    self?.lastErrorMessage = "Unable to start a saveable workout (\(error.localizedDescription)). Live data will be shown, but the workout will not be saved."
                    self?.pendingDisplayOnlyStart = true
                    self?.showingErrorAlert = true
                }
            } else if success {
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.bleLog.startSession(
                        reason: "workout_start",
                        appContext: Self.makeAppContext()
                    )
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
            } else {
                // Unknown failure: offer display-only after user dismisses alert
                DispatchQueue.main.async {
                    self?.alertTitle = "Limited Functionality"
                    self?.lastErrorMessage = "Unable to start a saveable workout. Live data will be shown, but the workout will not be saved."
                    self?.pendingDisplayOnlyStart = true
                    self?.showingErrorAlert = true
                }
            }
        }
    }

    private func resetDistanceTracking() {
        // Reset UI-facing distance and speed, and internal accumulation state
        distanceMeters = 0
        cyclingSpeedMps = 0
        lastDistanceUpdateTime = nil
        lastDistanceMetersSaved = 0
    }

    private func resetEnergyTracking() {
        lastEnergyUpdateTime = nil
        lastFTMSTotalEnergyKcal = nil
        hasSeenFTMSEnergy = false
    }

    private func resetHeartRateTracking() {
        prefersBikeHeartRate = false
        lastBikeHeartRateAt = nil
        DispatchQueue.main.async { self.heartRate = 0 }
    }

    func beginDisplayOnlyWorkoutIfPending() {
        guard pendingDisplayOnlyStart else { return }
        pendingDisplayOnlyStart = false
        bleLog.startSession(
            reason: "display_only_workout_start",
            appContext: Self.makeAppContext()
        )
        isDisplayOnlyMode = true
        isWorkoutActive = true
        hkManager.delegate = self
        hkManager.startHeartRateQuery()
        workoutTimer.onTick = { [weak self] seconds in self?.workoutDuration = seconds }
        workoutTimer.start()
        startScanning()
        lastEnergyUpdateTime = Date()
        lastDistanceUpdateTime = Date()
        lastDistanceMetersSaved = 0
    }
    
    private var pendingSaveAfterEnd: Bool = false

    func stopWorkout() {
        guard isWorkoutActive else { return }
        
        if isDisplayOnlyMode {
            // No save flow; just stop and reset
            DispatchQueue.main.async {
                self.isWorkoutActive = false
                self.isAwaitingSave = false
                self.workoutTimer.stop()
                self.hkManager.stopHeartRateQuery()
                self.stopScanning()
                self.resetDistanceTracking()
                self.resetEnergyTracking()
                self.resetHeartRateTracking()
                self.isDisplayOnlyMode = false
            }
            bleLog.endSession(reason: "display_only_workout_stop")
            return
        }

        // Immediately transition UI to save/discard and stop live sources
        DispatchQueue.main.async {
            self.isAwaitingSave = true
            self.isWorkoutActive = false
            self.workoutTimer.stop()
            self.hkManager.stopHeartRateQuery()
            self.stopScanning()
            self.resetDistanceTracking()
            self.resetEnergyTracking()
            self.resetHeartRateTracking()
            self.isEndingCollection = true
        }

        // End HealthKit collection in the background; when done, allow saving
        hkManager.endWorkoutCollection { success, error in
            if let error = error {
                print("Error ending workout collection: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                self.isEndingCollection = false
                if self.pendingSaveAfterEnd {
                    self.pendingSaveAfterEnd = false
                    self.finishWorkout()
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
                self.resetDistanceTracking()
            }
        }
        bleLog.endSession(reason: "workout_saved")
    }

    // MARK: - Post-workout actions
    func confirmSaveWorkout() {
        if isEndingCollection {
            pendingSaveAfterEnd = true
            return
        }
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
            self.distanceMeters = 0
            self.cyclingSpeedMps = 0
            self.resetEnergyTracking()
            self.resetHeartRateTracking()
            self.lastDistanceUpdateTime = nil
            self.lastDistanceMetersSaved = 0
        }
        bleLog.endSession(reason: "workout_discarded")
    }
    
    // Heart rate query handled by HealthKitManager
    
    // Workout timing handled by WorkoutTimer
    
    // MARK: - Bluetooth Scanning
    func startScanningForTesting() {
        bleLog.startSession(
            reason: "manual_scan_start",
            appContext: Self.makeAppContext()
        )
        bluetoothManager.startScanning()
    }
    
    func disconnectSensors() {
        bluetoothManager.stopScanning()
        bluetoothManager.disconnectAll()
        bleLog.endSession(reason: "manual_disconnect_sensors")
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

    private static func makeAppContext() -> [String: String] {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        return [
            "app": "CaPowHr",
            "version": version,
            "build": build,
            "platform": "watchOS"
        ]
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

        // Fallback energy estimation from mechanical power if the bike doesn't provide FTMS expended energy.
        // We only use this until we see FTMS totalEnergyKcal at least once, to avoid double-counting.
        guard !hasSeenFTMSEnergy else { return }
        let now = Date()
        if let last = lastEnergyUpdateTime {
            let dt = now.timeIntervalSince(last)
            if dt > 0 {
                let joules = watts * dt
                let kcal = joules / 4184.0
                if kcal > 0 {
                    hkManager.addEnergyBurnedSample(kcal, start: last, end: now)
                }
            }
        }
        lastEnergyUpdateTime = now
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

    func btDidUpdateFTMS(_ ftms: FTMSData) {
        // Prefer bike-reported HR when present and non-zero.
        if let hr = ftms.heartRateBpm, hr > 0 {
            let bpm = Double(hr)
            prefersBikeHeartRate = true
            lastBikeHeartRateAt = Date()
            DispatchQueue.main.async { self.heartRate = bpm }
            hkManager.addHeartRateSample(bpm)
        } else if prefersBikeHeartRate, let last = lastBikeHeartRateAt {
            // If bike HR disappears for a while, allow watch HR to take over again.
            // (We keep the watch HR query running, we just stop ignoring it.)
            if Date().timeIntervalSince(last) > 10 {
                prefersBikeHeartRate = false
            }
        }

        // Prefer device-reported expended energy (kcal) when present.
        if let total = ftms.totalEnergyKcal {
            let totalKcal = Double(total)
            let now = Date()
            hasSeenFTMSEnergy = true

            if let lastTotal = lastFTMSTotalEnergyKcal, let lastTime = lastEnergyUpdateTime {
                let delta = totalKcal - lastTotal
                // Guard against device reset/wrap or non-monotonic streams.
                if delta > 0 {
                    hkManager.addEnergyBurnedSample(delta, start: lastTime, end: now)
                }
            }

            lastFTMSTotalEnergyKcal = totalKcal
            lastEnergyUpdateTime = now
        }
    }
}

// MARK: - HealthKitManagerDelegate
extension WorkoutManager: HealthKitManagerDelegate {
    func hkDidUpdateHeartRate(_ bpm: Double) {
        // Only use watch HR if we are not actively receiving bike HR.
        if prefersBikeHeartRate { return }
        DispatchQueue.main.async { self.heartRate = bpm }
    }
}

// MARK: - CBPeripheralDelegate
// Peripheral delegate handled by BluetoothManager
