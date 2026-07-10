//
//  WorkoutManager.swift
//  CaPowHr Watch App
//
//  Created by Luke Mulcahy on 9/15/25.
//

import Foundation
import HealthKit
import CoreBluetooth

struct ScannedDevice: Identifiable, Hashable {
    let id: UUID
    let name: String
    let rssi: Int
    var iconName: String
}

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
    @Published var isWorkoutPaused: Bool = false
    @Published var isAwaitingSave: Bool = false
    @Published var isShowingWorkoutSummary: Bool = false
    @Published var isConnectingDuringWorkout: Bool = false
    @Published var isEndingCollection: Bool = false
    @Published var isSavingWorkout: Bool = false
    @Published var workoutSummary: WorkoutSummaryData?
    @Published var connectedDevices: [String] = []
    @Published var distanceMeters: Double = 0
    @Published var activeEnergyKcal: Double = 0
    @Published var isDisplayOnlyMode: Bool = false
    @Published var lastErrorMessage: String? = nil
    @Published var showingErrorAlert: Bool = false
    @Published var alertTitle: String? = nil

    @Published var pendingDisplayOnlyStart: Bool = false
    
    // MARK: - Discovery
    @Published var scannedDevices: [ScannedDevice] = []
    @Published var isScanning: Bool = false
    
    // MARK: - Treadmill-specific Properties
    @Published var detectedDeviceType: FitnessDeviceType = .unknown
    @Published var treadmillSpeedMps: Double = 0
    @Published var treadmillInclinePercent: Double = 0
    
    // MARK: - Rower-specific Properties
    @Published var rowerStrokeRatePerMinute: Double = 0
    @Published var rowerStrokeCount: UInt16 = 0
    @Published var rowerPaceSeconds500m: Double = 0
    
    // MARK: - Current Workout Type
    @Published var currentWorkoutType: WorkoutType = .indoorCycle
    @Published var structuredWorkout = StructuredWorkoutController()
    
    // MARK: - Health Services
    private let hkManager = HealthKitManager()
    private let statsTracker = WorkoutStatsTracker()
    
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
    private var prefersEquipmentHeartRate: Bool = false
    private var lastEquipmentHeartRateAt: Date?

    // MARK: - Stale metric timeout
    /// Instantaneous metrics freeze at their last value when a sensor stops
    /// notifying (e.g. the rider stops pedaling and crank events cease).
    /// Zero them when no update arrives within this window.
    private static let staleMetricTimeout: TimeInterval = 5
    private var lastPowerUpdateAt: Date?
    private var lastCadenceUpdateAt: Date?
    private var lastSpeedUpdateAt: Date?
    private var lastStrokeUpdateAt: Date?
    
    // MARK: - Heart Rate Source Preference
    private var heartRateSource: HeartRateSource {
        let rawValue = UserDefaults.standard.string(forKey: "heartRateSource") ?? HeartRateSource.auto.rawValue
        return HeartRateSource(rawValue: rawValue) ?? .auto
    }
    
    override init() {
        super.init()
        bluetoothManager.delegate = self
        WatchConnectivityManager.shared.activate()
        attemptReconnectToTrustedDevices()
    }

    func attemptReconnectToTrustedDevices() {
        let trusted = TrustedDeviceStore.loadAll()
        guard !trusted.isEmpty else { return }
        bluetoothManager.reconnectTrustedDevices(trusted.map(\.id))
    }
    
    // MARK: - HealthKit Authorization
    func requestHealthKitAuthorization() { hkManager.requestAuthorization() }
    
    // MARK: - Workout Control
    func startWorkout(type: WorkoutType = .indoorCycle, connectIfNeeded: Bool = false) {
        guard !isWorkoutActive else { return }
        currentWorkoutType = type
        AppSettings.lastWorkoutType = type

        let templateRaw = UserDefaults.standard.string(forKey: AppSettings.structuredWorkoutTemplateKey) ?? StructuredWorkoutTemplate.free.rawValue
        let template = StructuredWorkoutTemplate(rawValue: templateRaw) ?? .free
        structuredWorkout.start(template: template)

        if connectIfNeeded && connectedDevices.isEmpty {
            isConnectingDuringWorkout = true
            startScanning()
            if let trusted = TrustedDeviceStore.mostRecent() {
                bluetoothManager.reconnect(to: trusted.id)
            }
        }

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
                    self.isWorkoutPaused = false
                    self.hkManager.delegate = self
                    self.hkManager.startHeartRateQuery()
                    self.statsTracker.begin()
                    self.workoutTimer.onTick = { [weak self] seconds in
                        guard let self else { return }
                        self.workoutDuration = seconds
                        self.structuredWorkout.tick()
                        self.zeroStaleMetrics()
                    }
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
        prefersEquipmentHeartRate = false
        lastEquipmentHeartRateAt = nil
        DispatchQueue.main.async { self.heartRate = 0 }
    }

    func beginDisplayOnlyWorkoutIfPending() {
        guard pendingDisplayOnlyStart else { return }
        pendingDisplayOnlyStart = false
        isDisplayOnlyMode = true
        isWorkoutActive = true
        isWorkoutPaused = false
        hkManager.delegate = self
        hkManager.startHeartRateQuery()
        statsTracker.begin()
        workoutTimer.onTick = { [weak self] seconds in
            guard let self else { return }
            self.workoutDuration = seconds
            self.structuredWorkout.tick()
            self.zeroStaleMetrics()
        }
        workoutTimer.start()

        lastEnergyUpdateTime = Date()
        // Note: Do NOT initialize lastDistanceUpdateTime here. See comment in startWorkout().
        lastDistanceMetersSaved = 0
    }
    
    private var pendingSaveAfterEnd: Bool = false

    func pauseWorkout() {
        guard isWorkoutActive, !isWorkoutPaused else { return }
        isWorkoutPaused = true
        workoutTimer.pause()
        if !isDisplayOnlyMode {
            hkManager.pauseWorkout()
        }
    }

    func resumeWorkout() {
        guard isWorkoutActive, isWorkoutPaused else { return }
        isWorkoutPaused = false
        workoutTimer.resume()
        if !isDisplayOnlyMode {
            hkManager.resumeWorkout()
        }
        // Re-baseline the accumulators so anything the machine counted during the
        // pause (or a stale pre-pause timestamp) isn't booked as a burst on the
        // first post-resume packet.
        lastEnergyUpdateTime = Date()
        lastFTMSTotalEnergyKcal = nil
        lastDistanceUpdateTime = nil
        distanceEstimator.reset()
        cscDistanceEstimator.rebaseline()
    }

    func recordLap() {
        guard isWorkoutActive else { return }
        _ = statsTracker.recordLap(
            totalDistanceMeters: distanceMeters,
            durationSeconds: workoutDuration
        )
    }

    func stopWorkout() {
        guard isWorkoutActive else { return }
        stopScanning()
        isConnectingDuringWorkout = false

        if isDisplayOnlyMode {
            finalizeStoppedWorkout(save: false)
            return
        }

        workoutTimer.stop(reset: false)
        hkManager.stopHeartRateQuery()
        isWorkoutActive = false
        isWorkoutPaused = false
        isEndingCollection = true

        let summary = statsTracker.makeSummary(
            workoutType: currentWorkoutType,
            durationSeconds: workoutDuration,
            distanceMeters: distanceMeters,
            isDisplayOnlyMode: false
        )
        workoutSummary = summary

        hkManager.endWorkoutCollection { success, error in
            if let error = error {
                print("Error ending workout collection: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                self.isEndingCollection = false
                if self.pendingSaveAfterEnd {
                    self.pendingSaveAfterEnd = false
                    self.finishWorkout()
                } else if AppSettings.workoutSaveMode == .autoSave {
                    self.isAwaitingSave = true
                    self.confirmSaveWorkout()
                } else {
                    self.isShowingWorkoutSummary = true
                }
            }
        }
    }

    func proceedFromSummaryToSaveDiscard() {
        isShowingWorkoutSummary = false
        isAwaitingSave = true
    }

    private func finalizeStoppedWorkout(save: Bool) {
        DispatchQueue.main.async {
            self.isWorkoutActive = false
            self.isWorkoutPaused = false
            self.isAwaitingSave = false
            self.isShowingWorkoutSummary = false
            self.workoutTimer.stop()
            self.hkManager.stopHeartRateQuery()
            self.structuredWorkout.reset()
            if !save {
                self.resetWorkoutMetrics()
            }
            self.isDisplayOnlyMode = false
        }
    }

    private func resetWorkoutMetrics() {
        heartRate = 0
        cyclingPower = 0
        cyclingCadence = 0
        workoutDuration = 0
        activeEnergyKcal = 0
        resetDistanceTracking()
        resetEnergyTracking()
        resetHeartRateTracking()
        treadmillSpeedMps = 0
        treadmillInclinePercent = 0
        rowerStrokeRatePerMinute = 0
        rowerStrokeCount = 0
        rowerPaceSeconds500m = 0
        detectedDeviceType = .unknown
        workoutSummary = nil
        statsTracker.reset()
        lastPowerUpdateAt = nil
        lastCadenceUpdateAt = nil
        lastSpeedUpdateAt = nil
        lastStrokeUpdateAt = nil
    }

    /// Called from the 1 Hz workout tick: zero instantaneous metrics whose
    /// sensor stream has gone quiet so the display doesn't freeze at the
    /// last-received value after the rider stops.
    private func zeroStaleMetrics(now: Date = Date()) {
        func isStale(_ date: Date?) -> Bool {
            guard let date else { return false }
            return now.timeIntervalSince(date) > Self.staleMetricTimeout
        }
        if isStale(lastPowerUpdateAt) {
            cyclingPower = 0
            lastPowerUpdateAt = nil
        }
        if isStale(lastCadenceUpdateAt) {
            cyclingCadence = 0
            lastCadenceUpdateAt = nil
        }
        if isStale(lastSpeedUpdateAt) {
            cyclingSpeedMps = 0
            treadmillSpeedMps = 0
            lastSpeedUpdateAt = nil
        }
        if isStale(lastStrokeUpdateAt) {
            rowerStrokeRatePerMinute = 0
            rowerPaceSeconds500m = 0
            lastStrokeUpdateAt = nil
        }
    }
    
    private func finishWorkout() {
        if let summary = workoutSummary,
           let deviceName = connectedDevices.first {
            CompatibilityStore.recordSuccessfulWorkout(
                name: deviceName,
                deviceType: detectedDeviceType
            )
        }
        hkManager.finishWorkout { [weak self] success, _ in
            if success { print("Workout saved successfully") }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isAwaitingSave = false
                self.isShowingWorkoutSummary = false
                self.isSavingWorkout = false
                self.workoutTimer.stop()
                self.hkManager.stopHeartRateQuery()
                self.disconnectAllPeripherals()
                self.resetWorkoutMetrics()
                self.structuredWorkout.reset()
            }
        }
    }

    // MARK: - Post-workout actions
    func confirmSaveWorkout() {
        isSavingWorkout = true
        if isEndingCollection {
            pendingSaveAfterEnd = true
            return
        }
        finishWorkout()
    }
    
    func discardCurrentWorkout() {
        hkManager.discardWorkout()
        print("Workout discarded")
        finalizeStoppedWorkout(save: false)
    }
    
    // Heart rate query handled by HealthKitManager
    
    // Workout timing handled by WorkoutTimer
    
    // MARK: - Bluetooth Scanning
    func startScanning() {
        scannedDevices.removeAll() // Clear old results
        isScanning = true
        bluetoothManager.startScanning()
    }
    
    func stopScanning() {
        isScanning = false
        bluetoothManager.stopScanning()
    }
    
    func connect(to device: ScannedDevice) {
        bluetoothManager.connect(to: device.id)
        isScanning = false // Manager stops scanning on connect, but update UI state
    }
    
    func disconnectSensors() {
        stopScanning()
        bluetoothManager.disconnectAll()
    }
    
    private func disconnectAllPeripherals() {
        // Delegated to BluetoothManager
        bluetoothManager.disconnectAll()
        connectedDevices.removeAll()
    }
    
    // Sample writes are delegated to HealthKitManager
    
    /// Routes distance samples to the correct HealthKit type based on the current workout.
    private func addDistanceSampleForCurrentWorkout(_ meters: Double, start: Date, end: Date) {
        switch currentWorkoutType {
        case .indoorRun, .indoorWalk:
            hkManager.addWalkingRunningDistanceSample(meters, start: start, end: end)
        case .indoorCycle, .indoorRow:
            hkManager.addDistanceSample(meters, start: start, end: end)
        }
    }

    // MARK: - Shared equipment data handlers

    /// Applies an FTMS heart-rate field (bike, treadmill, or rower) according to the user's
    /// heart-rate source preference. `nil` means the packet omitted the HR field entirely,
    /// which is distinct from an explicit zero reading.
    private func handleEquipmentHeartRate(_ heartRateBpm: UInt8?) {
        let source = heartRateSource

        guard let hr = heartRateBpm else {
            // HR field missing from this packet.
            switch source {
            case .bike:
                prefersEquipmentHeartRate = true
                DispatchQueue.main.async { self.heartRate = 0 }
            case .watch:
                prefersEquipmentHeartRate = false
            case .auto:
                // If equipment HR disappears for a while, allow watch HR to take over again.
                if prefersEquipmentHeartRate, let last = lastEquipmentHeartRateAt,
                   Date().timeIntervalSince(last) > 10 {
                    prefersEquipmentHeartRate = false
                }
            }
            return
        }

        if hr > 0 {
            let bpm = Double(hr)
            lastEquipmentHeartRateAt = Date()
            switch source {
            case .bike, .auto:
                prefersEquipmentHeartRate = true
                DispatchQueue.main.async {
                    self.heartRate = bpm
                    // HR samples keep flowing to HealthKit during a pause (the chart
                    // should stay continuous) but shouldn't skew the workout average.
                    if !self.isWorkoutPaused { self.statsTracker.recordHeartRate(bpm) }
                }
                hkManager.addHeartRateSample(bpm)
            case .watch:
                prefersEquipmentHeartRate = false
            }
        } else {
            // Explicit zero: never let it "win" against the watch in auto mode.
            switch source {
            case .bike:
                prefersEquipmentHeartRate = true
                lastEquipmentHeartRateAt = nil
                DispatchQueue.main.async { self.heartRate = 0 }
            case .watch:
                prefersEquipmentHeartRate = false
            case .auto:
                prefersEquipmentHeartRate = false
                lastEquipmentHeartRateAt = nil
            }
        }
    }

    /// Applies an FTMS Expended Energy total (kcal) from any machine type, writing the delta
    /// to HealthKit. Marks FTMS energy as seen so the power-based fallback stops accumulating.
    private func handleEquipmentEnergy(totalKcal: UInt16?) {
        guard let total = totalKcal else { return }
        let totalKcalValue = Double(total)
        hasSeenFTMSEnergy = true

        // While paused, don't accrue energy; resumeWorkout() clears the baseline
        // so the first post-resume packet re-baselines against the machine total.
        guard !isWorkoutPaused else { return }

        let now = Date()
        if let lastTotal = lastFTMSTotalEnergyKcal, let lastTime = lastEnergyUpdateTime {
            let delta = totalKcalValue - lastTotal
            // Guard against device reset/wrap or non-monotonic streams.
            if delta > 0 {
                hkManager.addEnergyBurnedSample(delta, start: lastTime, end: now)
                // Accumulate deltas rather than mirroring the machine's session
                // total, so the displayed calories match what we record.
                DispatchQueue.main.async { self.activeEnergyKcal += delta }
            }
        }

        lastFTMSTotalEnergyKcal = totalKcalValue
        lastEnergyUpdateTime = now
    }
}

// MARK: - BluetoothManagerDelegate
extension WorkoutManager: BluetoothManagerDelegate {
    /// EMA factor for displayed RSSI. New samples get this weight; previous smoothed value gets (1 - alpha).
    /// Picked to track real signal-strength changes within ~1s while damping advert-to-advert jitter
    /// so rows in the picker don't swap on every packet.
    private static let rssiSmoothingAlpha: Double = 0.3

    func btDidDiscoverDevice(name: String, identifier: UUID, rssi: Int, advertisementData: [String: Any]) {
        let derivedIcon = Self.iconForAdvertisement(advertisementData)

        DispatchQueue.main.async {
            if let idx = self.scannedDevices.firstIndex(where: { $0.id == identifier }) {
                let prev = self.scannedDevices[idx]

                // Smooth RSSI so the displayed signal tracks reality but row order is stable.
                let alpha = Self.rssiSmoothingAlpha
                let smoothedRSSI = Int((Double(prev.rssi) * (1.0 - alpha) + Double(rssi) * alpha).rounded())

                // Don't downgrade a more-specific icon (e.g., "figure.run") to a generic one
                // ("sensor.fill" / "figure.mixed.cardio") just because this particular advert
                // packet happened to omit FTMS service data. BLE devices commonly rotate
                // between adv packets and scan responses, and only one of them carries the
                // full FTMS service data.
                let nextIcon = Self.iconSpecificity(derivedIcon) >= Self.iconSpecificity(prev.iconName)
                    ? derivedIcon
                    : prev.iconName

                self.scannedDevices[idx] = ScannedDevice(
                    id: identifier,
                    name: name,
                    rssi: smoothedRSSI,
                    iconName: nextIcon
                )
            } else {
                self.scannedDevices.append(
                    ScannedDevice(id: identifier, name: name, rssi: rssi, iconName: derivedIcon)
                )
            }

            // Strongest signal first (RSSI is negative; less negative = stronger).
            // Tie-break on UUID so rows with identical smoothed RSSI don't swap on every update.
            self.scannedDevices.sort { lhs, rhs in
                if lhs.rssi != rhs.rssi { return lhs.rssi > rhs.rssi }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        }
    }

    /// Higher = more confident classification. Used to avoid replacing a specific icon with
    /// a generic one when a later advert packet doesn't include FTMS service data.
    private static func iconSpecificity(_ icon: String) -> Int {
        switch icon {
        case "sensor.fill": return 0          // unknown
        case "figure.mixed.cardio": return 1  // generic FTMS
        default: return 2                     // specific machine type
        }
    }

    /// Derive a SF Symbol name from an advertisement packet. Returns the most specific icon
    /// the packet supports; callers should prefer the highest-specificity icon seen so far.
    private static func iconForAdvertisement(_ advertisementData: [String: Any]) -> String {
        var icon = "sensor.fill" // Default

        // 1. Check Service UUIDs for basic classification.
        if let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            if services.contains(BluetoothUUIDs.Service.cyclingSpeedCadence) ||
               services.contains(BluetoothUUIDs.Service.cyclingPower) {
                icon = "bicycle"
            } else if services.contains(BluetoothUUIDs.Service.fitnessMachine) {
                // FTMS - fallback before service-data parse below may refine it.
                icon = "figure.mixed.cardio"
            }
        }

        // 2. Parse FTMS Service Data for machine type (preferred method).
        // FTMS v1.0 advertisement data format: Byte 0 = Flags, Bytes 1-2 = Fitness Machine Type
        // (little-endian bitfield).
        // Bit definitions for Fitness Machine Type:
        //   Bit 0: Treadmill Supported
        //   Bit 1: Cross Trainer Supported
        //   Bit 2: Step Climber Supported
        //   Bit 3: Stair Climber Supported
        //   Bit 4: Rower Supported
        //   Bit 5: Indoor Bike Supported
        if let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
           let ftmsData = serviceData[BluetoothUUIDs.Service.fitnessMachine],
           ftmsData.count >= 3 {
            let machineType = UInt16(ftmsData[1]) | (UInt16(ftmsData[2]) << 8)

            // Check bits in priority order (most specific first).
            if (machineType & 0x0001) != 0 {
                icon = "figure.run"           // Treadmill
            } else if (machineType & 0x0010) != 0 {
                icon = "oar.2.crossed"        // Rower
            } else if (machineType & 0x0020) != 0 {
                icon = "bicycle"              // Indoor Bike
            } else if (machineType & 0x0002) != 0 {
                icon = "figure.elliptical"    // Cross Trainer
            } else if (machineType & 0x000C) != 0 {
                icon = "figure.stairs"        // Step / Stair Climber
            }
        }

        return icon
    }
    
    func btDidConnect(to name: String) {
        DispatchQueue.main.async {
            if !self.connectedDevices.contains(name) { self.connectedDevices.append(name) }
            self.isConnectingDuringWorkout = false
        }
    }

    func btDidConnectDevice(id: UUID, name: String, deviceType: FitnessDeviceType) {
        DispatchQueue.main.async {
            TrustedDeviceStore.remember(id: id, name: name, deviceType: deviceType)
            CompatibilityStore.recordSuccessfulConnection(name: name, deviceType: deviceType)
            if self.detectedDeviceType == .unknown, deviceType != .unknown {
                self.detectedDeviceType = deviceType
            }
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
        lastPowerUpdateAt = Date()
        DispatchQueue.main.async {
            self.cyclingPower = watts
            if !self.isWorkoutPaused { self.statsTracker.recordPower(watts) }
        }
        // While paused, keep showing live values but don't record samples or
        // accrue energy; resumeWorkout() re-baselines the accumulators.
        guard !isWorkoutPaused else { return }
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
                    DispatchQueue.main.async { self.activeEnergyKcal += kcal }
                }
            }
        }
        lastEnergyUpdateTime = now
    }

    func btDidUpdateCadence(rpm: Double) {
        lastCadenceUpdateAt = Date()
        DispatchQueue.main.async {
            self.cyclingCadence = rpm
            if !self.isWorkoutPaused { self.statsTracker.recordCadence(rpm) }
        }
        guard !isWorkoutPaused else { return }
        hkManager.addCadenceSample(rpm)
    }

    func btDidUpdateSpeed(mps: Double) {
        lastSpeedUpdateAt = Date()
        DispatchQueue.main.async { self.cyclingSpeedMps = mps }

        // Cache latest speed for CSC circumference calibration.
        lastSpeedForCSCCalibrationMps = mps

        // While paused, show live speed but don't write samples or integrate distance.
        guard !isWorkoutPaused else { return }

        if currentWorkoutType == .indoorRun {
            hkManager.addSpeedSample(mps, isRunning: true)
        } else if currentWorkoutType == .indoorWalk {
            hkManager.addSpeedSample(mps, isRunning: false)
        }

        // If the bike provides cumulative distance, prefer that.
        guard !hasSeenFTMSTotalDistance else { return }

        // If CSC wheel distance is active, prefer CSC-based distance rather than integrating speed.
        guard !hasSeenCSCDistance else { return }

        let now = Date()
        guard let sample = distanceEstimator.update(speedMps: mps, now: now) else { return }

        // Update the UI-facing cumulative distance and write HealthKit delta samples.
        DispatchQueue.main.async { self.distanceMeters += sample.deltaMeters }
        addDistanceSampleForCurrentWorkout(sample.deltaMeters, start: sample.start, end: sample.end)
    }

    func btDidUpdateTotalDistance(meters: Double) {
        hasSeenFTMSTotalDistance = true
        distanceEstimator.reset()
        cscDistanceEstimator.reset()

        // While paused, ignore machine totals entirely; resumeWorkout() clears
        // lastDistanceUpdateTime so the next packet re-baselines against the
        // machine's cumulative counter and pause movement is excluded.
        guard !isWorkoutPaused else { return }

        let now = Date()
        if let lastTime = lastDistanceUpdateTime {
            let delta = meters - lastDistanceMetersSaved
            if delta > 0 {
                addDistanceSampleForCurrentWorkout(delta, start: lastTime, end: now)
                let dt = now.timeIntervalSince(lastTime)
                if dt > 0 {
                    lastSpeedUpdateAt = now
                    DispatchQueue.main.async { self.cyclingSpeedMps = delta / dt }
                }
                // Accumulate deltas rather than mirroring the machine's session
                // total, so the displayed distance matches what we record.
                DispatchQueue.main.async { self.distanceMeters += delta }
            }
        }
        // Always advance the baselines: stalled frames (delta == 0) shouldn't
        // stretch the next sample's time window and skew the derived speed, and
        // a device counter reset (delta < 0) should re-baseline immediately
        // instead of blocking all future samples until the counter catches up.
        lastDistanceMetersSaved = meters
        lastDistanceUpdateTime = now
    }
    
    func btDidUpdateConnectedDevices(_ names: [String]) {
        DispatchQueue.main.async { self.connectedDevices = names }
    }

    func btDidUpdateIndoorBike(_ bikeData: IndoorBikeData) {
        handleEquipmentHeartRate(bikeData.heartRateBpm)
        handleEquipmentEnergy(totalKcal: bikeData.totalEnergyKcal)
    }

    func btDidUpdateCSC(wheelRev: UInt32?, wheelTime: UInt16?, crankRev: UInt16?, crankTime: UInt16?) {
        // Distance estimation from CSC wheel data (if present). Many bikes send crank-only; in that case we do nothing.
        guard !hasSeenFTMSTotalDistance else { return }
        guard let rev = wheelRev, let time = wheelTime else { return }

        // While paused, don't accrue wheel distance; resumeWorkout() re-baselines
        // the estimator so pause revolutions aren't counted.
        guard !isWorkoutPaused else { return }

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
        addDistanceSampleForCurrentWorkout(deltaMeters, start: start, end: end)
    }

    func btDidUpdateTreadmill(_ treadmill: TreadmillData) {
        // Update treadmill-specific metrics
        if let speedMps = treadmill.instantaneousSpeedMps {
            lastSpeedUpdateAt = Date()
            DispatchQueue.main.async { self.treadmillSpeedMps = speedMps }
            if currentWorkoutType == .indoorRun {
                hkManager.addSpeedSample(speedMps, isRunning: true)
            } else if currentWorkoutType == .indoorWalk {
                hkManager.addSpeedSample(speedMps, isRunning: false)
            }
        }
        if let incline = treadmill.inclinePercent {
            DispatchQueue.main.async { self.treadmillInclinePercent = incline }
        }

        handleEquipmentHeartRate(treadmill.heartRateBpm)
        handleEquipmentEnergy(totalKcal: treadmill.totalEnergyKcal)
    }

    func btDidUpdateRower(_ rower: RowerData) {
        // Update rower-specific metrics
        if let strokeRate = rower.strokeRatePerMinute {
            lastStrokeUpdateAt = Date()
            DispatchQueue.main.async { self.rowerStrokeRatePerMinute = strokeRate }
        }
        if let strokeCount = rower.strokeCount {
            DispatchQueue.main.async { self.rowerStrokeCount = strokeCount }
        }
        if let pace = rower.instantaneousPaceSeconds500m {
            lastStrokeUpdateAt = Date()
            DispatchQueue.main.async { self.rowerPaceSeconds500m = pace }
        }

        handleEquipmentHeartRate(rower.heartRateBpm)
        handleEquipmentEnergy(totalKcal: rower.totalEnergyKcal)
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
            DispatchQueue.main.async {
                self.heartRate = bpm
                if !self.isWorkoutPaused { self.statsTracker.recordHeartRate(bpm) }
            }
            hkManager.addHeartRateSample(bpm)
        case .auto:
            // Auto mode: only use watch HR if we are not actively receiving equipment HR
            if prefersEquipmentHeartRate { return }
            DispatchQueue.main.async {
                self.heartRate = bpm
                if !self.isWorkoutPaused { self.statsTracker.recordHeartRate(bpm) }
            }
            hkManager.addHeartRateSample(bpm)
        }
    }
}

