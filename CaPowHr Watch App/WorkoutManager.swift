//
//  WorkoutManager.swift
//  CaPowHr Watch App
//
//  Created by Luke Mulcahy on 9/15/25.
//

import Foundation
import HealthKit

enum HeartRateSource: String, CaseIterable {
    case auto = "auto"
    case bike = "bike"
    case watch = "watch"
    
    var displayName: String {
        switch self {
        case .auto: return "Auto (default)"
        case .bike: return "Bike"
        case .watch: return "Apple Watch"
        }
    }
}

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
    @Published var connectedDevices: [String] = []
    @Published var distanceMeters: Double = 0
    @Published var isDisplayOnlyMode: Bool = false
    @Published var lastErrorMessage: String? = nil
    @Published var showingErrorAlert: Bool = false
    @Published var alertTitle: String? = nil
    @Published var pendingDisplayOnlyStart: Bool = false
    
    // MARK: - Treadmill-specific Properties
    @Published var detectedDeviceType: FitnessDeviceType = .unknown
    @Published var treadmillSpeedMps: Double = 0
    @Published var treadmillInclinePercent: Double = 0
    
    // MARK: - Current Workout Type
    @Published var currentWorkoutType: WorkoutType = .indoorCycle
    
    // MARK: - Health Services
    private let hkManager = HealthKitManager()
    
    // MARK: - CoreBluetooth
    private let bluetoothManager = BluetoothManager()
    
    // MARK: - Workout Timer
    private let workoutTimer = WorkoutTimer()

    
    // MARK: - HealthKit accumulation state
    private var lastEnergyUpdateTime: Date?
    private var lastDistanceUpdateTime: Date?
    private var lastDistanceMetersSaved: Double = 0
    private var hasSeenFTMSTotalDistance: Bool = false
    private var distanceEstimator = DistanceEstimator()
    private var cscDistanceEstimator = CSCDistanceEstimator()
    private var hasSeenCSCDistance: Bool = false
    private var lastSpeedForCSCCalibrationMps: Double?
    private var hasSeenFTMSEnergy: Bool = false
    private var lastFTMSTotalEnergyKcal: Double?
    private var prefersBikeHeartRate: Bool = false
    private var lastBikeHeartRateAt: Date?
    
    // MARK: - Heart Rate Source Preference
    private var heartRateSource: HeartRateSource {
        let rawValue = UserDefaults.standard.string(forKey: "heartRateSource") ?? HeartRateSource.auto.rawValue
        return HeartRateSource(rawValue: rawValue) ?? .auto
    }
    
    override init() {
        super.init()
        bluetoothManager.delegate = self
    }
    
    // MARK: - HealthKit Authorization
    func requestHealthKitAuthorization() { hkManager.requestAuthorization() }
    
    // MARK: - Workout Control
    func startWorkout(type: WorkoutType = .indoorCycle) {
        guard !isWorkoutActive else { return }
        currentWorkoutType = type

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

        let configuration = hkManager.configuration(for: type)
        
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
                    self.isWorkoutActive = true
                    self.hkManager.delegate = self
                    self.hkManager.startHeartRateQuery()
                    self.workoutTimer.onTick = { [weak self] seconds in self?.workoutDuration = seconds }
                    self.workoutTimer.start()

                    self.lastEnergyUpdateTime = Date()
                    // Note: Do NOT initialize lastDistanceUpdateTime here. If the bike
                    // provides totalDistanceMeters, the first call to btDidUpdateTotalDistance
                    // will establish the baseline. If we set it here, we risk double-counting
                    // distance when transitioning from speed-integration to total-distance mode.
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
        hasSeenFTMSTotalDistance = false
        distanceEstimator.reset()
        cscDistanceEstimator.reset()
        hasSeenCSCDistance = false
        lastSpeedForCSCCalibrationMps = nil
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
        isDisplayOnlyMode = true
        isWorkoutActive = true
        hkManager.delegate = self
        hkManager.startHeartRateQuery()
        workoutTimer.onTick = { [weak self] seconds in self?.workoutDuration = seconds }
        workoutTimer.start()

        lastEnergyUpdateTime = Date()
        // Note: Do NOT initialize lastDistanceUpdateTime here. See comment in startWorkout().
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

                self.resetDistanceTracking()
                self.resetEnergyTracking()
                self.resetHeartRateTracking()
                self.treadmillSpeedMps = 0
                self.treadmillInclinePercent = 0
                self.detectedDeviceType = .unknown
                self.isDisplayOnlyMode = false
            }
            return
        }

        // Immediately transition UI to save/discard and stop live sources
        DispatchQueue.main.async {
            self.isAwaitingSave = true
            self.isWorkoutActive = false
            self.workoutTimer.stop()
            self.hkManager.stopHeartRateQuery()

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
                self.treadmillSpeedMps = 0
                self.treadmillInclinePercent = 0
                self.detectedDeviceType = .unknown
            }
        }
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
            self.treadmillSpeedMps = 0
            self.treadmillInclinePercent = 0
            self.detectedDeviceType = .unknown
            self.resetEnergyTracking()
            self.resetHeartRateTracking()
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
    

    
    private func disconnectAllPeripherals() {
        // Delegated to BluetoothManager
        bluetoothManager.disconnectAll()
        connectedDevices.removeAll()
    }
    
    // Sample writes are delegated to HealthKitManager
}

// MARK: - BluetoothManagerDelegate
extension WorkoutManager: BluetoothManagerDelegate {
    func btDidDiscoverCyclingDevice(name: String) {
        print("Found cycling device: \(name)")
    }
    
    func btDidConnect(to name: String) {
        DispatchQueue.main.async {
            if !self.connectedDevices.contains(name) { self.connectedDevices.append(name) }
        }
    }
    
    func btDidFailToConnect(name: String, error: Error?) {
        print("Failed to connect to: \(name) error: \(error?.localizedDescription ?? "unknown")")
    }
    
    func btDidDisconnect(name: String, error: Error?) {
        DispatchQueue.main.async {
            self.connectedDevices.removeAll { $0 == name }
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

        // Cache latest speed for CSC circumference calibration.
        lastSpeedForCSCCalibrationMps = mps

        // If the bike provides cumulative distance, prefer that.
        guard !hasSeenFTMSTotalDistance else { return }

        // If CSC wheel distance is active, prefer CSC-based distance rather than integrating speed.
        guard !hasSeenCSCDistance else { return }

        let now = Date()
        guard let sample = distanceEstimator.update(speedMps: mps, now: now) else { return }

        // Update the UI-facing cumulative distance and write HealthKit delta samples.
        DispatchQueue.main.async { self.distanceMeters += sample.deltaMeters }
        hkManager.addDistanceSample(sample.deltaMeters, start: sample.start, end: sample.end)
    }
    
    func btDidUpdateTotalDistance(meters: Double) {
        hasSeenFTMSTotalDistance = true
        distanceEstimator.reset()
        cscDistanceEstimator.reset()
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

    func btDidUpdateIndoorBike(_ bikeData: IndoorBikeData) {
        let source = heartRateSource
        
        // Handle bike heart rate data based on user preference
        if let hr = bikeData.heartRateBpm {
            if hr > 0 {
                let bpm = Double(hr)
                lastBikeHeartRateAt = Date()
                
                switch source {
                case .bike:
                    // Always use bike HR when preference is bike
                    prefersBikeHeartRate = true
                    DispatchQueue.main.async { self.heartRate = bpm }
                    hkManager.addHeartRateSample(bpm)
                case .watch:
                    // Ignore bike HR when preference is watch
                    prefersBikeHeartRate = false
                case .auto:
                    // Auto mode: prefer bike HR when present and non-zero
                    prefersBikeHeartRate = true
                    DispatchQueue.main.async { self.heartRate = bpm }
                    hkManager.addHeartRateSample(bpm)
                }
            } else {
                // Explicit zero: handle based on mode
                switch source {
                case .bike:
                    // In bike mode, set HR to zero when bike reports zero
                    prefersBikeHeartRate = true
                    lastBikeHeartRateAt = nil
                    DispatchQueue.main.async { self.heartRate = 0 }
                case .watch:
                    // In watch mode, ignore bike HR
                    prefersBikeHeartRate = false
                case .auto:
                    // Auto mode: explicit zero should not "win" against the watch
                    prefersBikeHeartRate = false
                    lastBikeHeartRateAt = nil
                }
            }
        } else {
            // Bike HR field is missing from FTMS data
            switch source {
            case .bike:
                // In bike mode, set HR to zero when bike HR is not available
                prefersBikeHeartRate = true
                DispatchQueue.main.async { self.heartRate = 0 }
            case .watch:
                // In watch mode, ignore bike HR
                prefersBikeHeartRate = false
            case .auto:
                // Auto mode: If bike HR disappears for a while, allow watch HR to take over again
                if prefersBikeHeartRate, let last = lastBikeHeartRateAt {
                    if Date().timeIntervalSince(last) > 10 {
                        prefersBikeHeartRate = false
                    }
                }
            }
        }

        // Prefer device-reported expended energy (kcal) when present.
        if let total = bikeData.totalEnergyKcal {
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

    func btDidUpdateCSC(wheelRev: UInt32?, wheelTime: UInt16?, crankRev: UInt16?, crankTime: UInt16?) {
        // Distance estimation from CSC wheel data (if present). Many bikes send crank-only; in that case we do nothing.
        guard !hasSeenFTMSTotalDistance else { return }
        guard let rev = wheelRev, let time = wheelTime else { return }

        // Mark CSC distance as our preferred non-FTMS-distance source and disable speed integration.
        hasSeenCSCDistance = true
        distanceEstimator.reset()

        let delta = cscDistanceEstimator.update(
            wheelRev: rev,
            wheelTime: time,
            speedMpsForCalibration: lastSpeedForCSCCalibrationMps
        )
        guard let deltaMeters = delta, deltaMeters > 0 else { return }

        DispatchQueue.main.async { self.distanceMeters += deltaMeters }

        // We don't have absolute timestamps from CSC ticks, so use wall clock for HealthKit sample bounds.
        // The delta is still correct; the time window just reflects arrival cadence.
        let end = Date()
        let start = end.addingTimeInterval(-1)
        hkManager.addDistanceSample(deltaMeters, start: start, end: end)
    }

    func btDidUpdateTreadmill(_ treadmill: TreadmillData) {
        // Update treadmill-specific metrics
        if let speedMps = treadmill.instantaneousSpeedMps {
            DispatchQueue.main.async { self.treadmillSpeedMps = speedMps }
        }
        if let incline = treadmill.inclinePercent {
            DispatchQueue.main.async { self.treadmillInclinePercent = incline }
        }
        
        // Handle heart rate from treadmill
        let source = heartRateSource
        if let hr = treadmill.heartRateBpm {
            if hr > 0 {
                let bpm = Double(hr)
                lastBikeHeartRateAt = Date()
                
                switch source {
                case .bike:
                    // "bike" preference means prefer equipment HR
                    prefersBikeHeartRate = true
                    DispatchQueue.main.async { self.heartRate = bpm }
                    hkManager.addHeartRateSample(bpm)
                case .watch:
                    prefersBikeHeartRate = false
                case .auto:
                    prefersBikeHeartRate = true
                    DispatchQueue.main.async { self.heartRate = bpm }
                    hkManager.addHeartRateSample(bpm)
                }
            } else {
                switch source {
                case .bike:
                    prefersBikeHeartRate = true
                    lastBikeHeartRateAt = nil
                    DispatchQueue.main.async { self.heartRate = 0 }
                case .watch:
                    prefersBikeHeartRate = false
                case .auto:
                    prefersBikeHeartRate = false
                    lastBikeHeartRateAt = nil
                }
            }
        }
        
        // Handle energy from treadmill (same logic as bike)
        if let total = treadmill.totalEnergyKcal {
            let totalKcal = Double(total)
            let now = Date()
            hasSeenFTMSEnergy = true
            
            if let lastTotal = lastFTMSTotalEnergyKcal, let lastTime = lastEnergyUpdateTime {
                let delta = totalKcal - lastTotal
                if delta > 0 {
                    hkManager.addEnergyBurnedSample(delta, start: lastTime, end: now)
                }
            }
            
            lastFTMSTotalEnergyKcal = totalKcal
            lastEnergyUpdateTime = now
        }
    }

    func btDidDetectDeviceType(_ type: FitnessDeviceType) {
        DispatchQueue.main.async {
            self.detectedDeviceType = type
        }
    }
}

// MARK: - HealthKitManagerDelegate
extension WorkoutManager: HealthKitManagerDelegate {
    func hkDidUpdateHeartRate(_ bpm: Double) {
        let source = heartRateSource
        
        switch source {
        case .bike:
            // In bike mode, always ignore watch HR - only use bike HR or show zero
            return
        case .watch:
            // In watch mode, always use watch HR
            DispatchQueue.main.async { self.heartRate = bpm }
            hkManager.addHeartRateSample(bpm)
        case .auto:
            // Auto mode: only use watch HR if we are not actively receiving bike HR
            if prefersBikeHeartRate { return }
            DispatchQueue.main.async { self.heartRate = bpm }
            hkManager.addHeartRateSample(bpm)
        }
    }
}

