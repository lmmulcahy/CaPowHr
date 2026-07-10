import Foundation
import CoreBluetooth

// MARK: - Bluetooth UUIDs
//
// Standard Bluetooth SIG UUIDs for cycling-related services and characteristics.

enum BluetoothUUIDs {
    enum Service {
        /// Cycling Power Service (0x1818)
        static let cyclingPower = CBUUID(string: "1818")
        /// Cycling Speed and Cadence Service (0x1816)
        static let cyclingSpeedCadence = CBUUID(string: "1816")
        /// Fitness Machine Service (0x1826)
        static let fitnessMachine = CBUUID(string: "1826")

        /// All cycling-related services for scanning
        static let allCycling: [CBUUID] = [cyclingPower, cyclingSpeedCadence, fitnessMachine]
    }

    enum Characteristic {
        /// Cycling Power Measurement (0x2A63)
        static let powerMeasurement = CBUUID(string: "2A63")
        /// CSC Measurement (0x2A5B)
        static let cscMeasurement = CBUUID(string: "2A5B")
        /// FTMS Indoor Bike Data (0x2AD2)
        static let indoorBikeData = CBUUID(string: "2AD2")
        /// FTMS Treadmill Data (0x2ACD)
        static let treadmillData = CBUUID(string: "2ACD")
        /// FTMS Rower Data (0x2AD1)
        static let rowerData = CBUUID(string: "2AD1")
    }
}

// MARK: - BluetoothManager & Delegate
//
// This file encapsulates the watchOS CoreBluetooth flow for cycling sensors.
// Responsibilities:
// - Run a two-phase scan (broad → filtered) to discover peripherals
// - Connect to peripherals advertising cycling services (CSC, FTMS, Cycling Power)
// - Maintain connection state to avoid duplicate connections and to keep peripherals alive
// - Discover characteristics and subscribe (notifications) for data streams
// - Route raw data to CyclingSensorParser/TreadmillSensorParser and emit updates to the app via delegate callbacks
//
// Notes on watchOS/CoreBluetooth behavior that inform the design:
// - You must keep a strong reference to CBPeripheral while connecting/connected to avoid API MISUSE
// - Scanning while connecting can delay or interfere with connections; we stop scanning before connect
// - We allow duplicate advertisement callbacks so the device picker can show a live RSSI per peripheral.
//   The list view uses smoothed RSSI to keep rows from jittering. Scanning is bounded to the picker's
//   lifecycle (and brief auto-restart windows after disconnect/fail), so the extra callbacks are cheap.

/// Delegate for receiving device lifecycle events and parsed sensor updates.
/// Implemented by higher-level coordinators (e.g., WorkoutManager).
protocol BluetoothManagerDelegate: AnyObject {
    /// Called when we discover a peripheral that advertises cycling services.
    /// Called when we discover a peripheral with cycling/fitness services.
    func btDidDiscoverDevice(name: String, identifier: UUID, rssi: Int, advertisementData: [String: Any])
    /// Called after a successful CoreBluetooth connection.
    func btDidConnect(to name: String)
    /// Called when CoreBluetooth fails to connect to a peripheral.
    func btDidFailToConnect(name: String, error: Error?)
    /// Called on disconnect (with optional error for cause).
    func btDidDisconnect(name: String, error: Error?)
    /// Parsed instantaneous power in watts.
    func btDidUpdatePower(watts: Double)
    /// Parsed instantaneous cadence in RPM.
    func btDidUpdateCadence(rpm: Double)
    /// Parsed instantaneous speed in m/s.
    func btDidUpdateSpeed(mps: Double)
    /// Parsed total distance in meters (cumulative).
    func btDidUpdateTotalDistance(meters: Double)
    /// Full parsed FTMS Indoor Bike Data packet (includes fields we may not display).
    func btDidUpdateIndoorBike(_ data: IndoorBikeData)
    /// Full parsed FTMS Treadmill Data packet.
    func btDidUpdateTreadmill(_ treadmill: TreadmillData)
    /// Full parsed FTMS Rower Data packet.
    func btDidUpdateRower(_ rower: RowerData)
    /// Called when the device type is detected (bike vs treadmill).
    func btDidDetectDeviceType(_ type: FitnessDeviceType)
    /// Emitted whenever the set of connected devices changes.
    func btDidUpdateConnectedDevices(_ names: [String])
    /// Called after a successful connection with stable peripheral identity.
    func btDidConnectDevice(id: UUID, name: String, deviceType: FitnessDeviceType)

    /// Raw parsed CSC Measurement values (0x2A5B). Used for distance estimation when wheel data is present.
    func btDidUpdateCSC(wheelRev: UInt32?, wheelTime: UInt16?, crankRev: UInt16?, crankTime: UInt16?)

    /// Emitted whenever scanning starts or stops, including the automatic restarts
    /// after a disconnect/failed connect, so UI state can track the real radio state.
    func btDidChangeScanningState(_ isScanning: Bool)
}

final class BluetoothManager: NSObject {
    /// App-level receiver of events and metrics.
    weak var delegate: BluetoothManagerDelegate?

    /// CoreBluetooth central; configured with self as the delegate.
    private var centralManager: CBCentralManager!
    /// Tracks whether a scan is currently active to avoid re-entrant scans.
    private(set) var isScanning: Bool = false

    /// Strong references to maintain connections while in .connected state.
    private var connectedPeripherals: [CBPeripheral] = []
    /// Strong references to keep peripherals alive while connecting.
    private var connectingPeripherals: [CBPeripheral] = []
    private var detectedDeviceTypes: [UUID: FitnessDeviceType] = [:]
    
    /// Cached display names keyed by `CBPeripheral.identifier`.
    /// `CBPeripheral.name` is frequently nil on first discovery/connect; the advertisement local name is often the best initial value.
    private var peripheralNameCache: [UUID: String] = [:]
    /// Controls whether the manager should automatically resume scanning after disconnect/fail.
    private var allowAutoReconnect: Bool = true
    /// If scanning is requested before Bluetooth is powered on, we defer and auto-start once it becomes powered on.
    /// If scanning is requested before Bluetooth is powered on, we defer and auto-start once it becomes powered on.
    private var pendingScanWhenPoweredOn: Bool = false
    
    /// Keep track of discovered peripherals so we can connect to them by UUID later.
    private var discoveredPeripheralsDict: [UUID: CBPeripheral] = [:]

    // CSC cadence tracking (for wrap-safe cadence deltas)
    private var cscLastCrankTime: UInt16 = 0
    private var cscLastCrankCount: UInt16 = 0

    /// Resets CSC tracking state. Call when disconnecting to avoid stale deltas on reconnect.
    private func resetCSCState() {
        cscLastCrankTime = 0
        cscLastCrankCount = 0
    }

    override init() {
        super.init()
        // Set self as the central delegate so we receive discovery/connection callbacks
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    /// Begin a two-phase scan: broad scan first, then narrow to specific services.
    /// On watchOS this pattern finds devices that may not advertise services immediately.
    func startScanning() {
        // Avoid starting a second concurrent scan
        if isScanning { return }
        // Require Bluetooth to be powered on
        guard centralManager.state == .poweredOn else {
            pendingScanWhenPoweredOn = true
            print("Bluetooth not powered on, state: \(centralManager.state.rawValue)")
            return
        }
        pendingScanWhenPoweredOn = false
        // User explicitly began scanning; allow auto-reconnect behavior going forward
        allowAutoReconnect = true
        isScanning = true
        delegate?.btDidChangeScanningState(true)
        print("Starting Bluetooth scan for cycling services...")
        BluetoothLogManager.shared.logScanStart()
        // Phase 1: broad scan for any peripheral (no service filter)
        // We will filter in didDiscover.
        // AllowDuplicatesKey: true lets every advertisement through so the picker can show a
        // live (smoothed) RSSI per peripheral instead of a frozen first-seen value.
        discoveredPeripheralsDict.removeAll()
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        // After a short window, narrow to cycling services to reduce noise
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self else { return }
            if self.isScanning {
                print("Switching to specific service scanning...")
                self.centralManager.stopScan()
                self.centralManager.scanForPeripherals(
                    withServices: BluetoothUUIDs.Service.allCycling,
                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
                )
            }
        }
    }

    /// Stop scanning if active to conserve power and reduce radio contention.
    func stopScanning() {
        if !isScanning { return }
        isScanning = false
        delegate?.btDidChangeScanningState(false)
        print("Stopping Bluetooth scan...")
        BluetoothLogManager.shared.logScanStop()
        centralManager.stopScan()
    }

    /// Cancel all active and in-progress connections, and emit an empty device list.
    func disconnectAll() {
        // User explicitly requested disconnect; suppress auto-reconnect until scanning is started again
        allowAutoReconnect = false
        for p in connectedPeripherals { centralManager.cancelPeripheralConnection(p) }
        for p in connectingPeripherals { centralManager.cancelPeripheralConnection(p) }
        connectedPeripherals.removeAll()
        connectingPeripherals.removeAll()
        peripheralNameCache.removeAll()
        resetCSCState()
        delegate?.btDidUpdateConnectedDevices([])
    }
    
    private func cachedDisplayName(for peripheral: CBPeripheral) -> String {
        if let cached = peripheralNameCache[peripheral.identifier], !cached.isEmpty { return cached }
        if let n = peripheral.name, !n.isEmpty {
            peripheralNameCache[peripheral.identifier] = n
            return n
        }
        return "Unknown"
    }
    
    private func updateCachedName(from advertisementData: [String: Any], for peripheral: CBPeripheral) -> String? {
        // Prefer the advertised local name when present.
        if let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String, !advName.isEmpty {
            peripheralNameCache[peripheral.identifier] = advName
            return advName
        }
        // Fall back to whatever CoreBluetooth currently exposes.
        if let n = peripheral.name, !n.isEmpty {
            peripheralNameCache[peripheral.identifier] = n
            return n
        }
            return nil
    }
    
    /// User selected a device to connect to.
    func connect(to identifier: UUID) {
        guard let peripheral = discoveredPeripheralsDict[identifier] else {
            print("Peripheral \(identifier) not found in discovered list.")
            return
        }
        connect(peripheral: peripheral)
    }

    func connect(peripheral: CBPeripheral) {
        stopScanning()
        if !connectedPeripherals.contains(peripheral) && !connectingPeripherals.contains(peripheral) {
            connectingPeripherals.append(peripheral)
            print("Connecting to \(cachedDisplayName(for: peripheral))...")
            centralManager.connect(peripheral, options: nil)
        }
    }

    /// Attempt to reconnect to a previously trusted device by UUID.
    func reconnect(to identifier: UUID) {
        guard centralManager.state == .poweredOn else { return }
        if let existing = connectedPeripherals.first(where: { $0.identifier == identifier }) {
            delegate?.btDidConnect(to: cachedDisplayName(for: existing))
            delegate?.btDidUpdateConnectedDevices(connectedPeripherals.map { cachedDisplayName(for: $0) })
            return
        }
        if let cached = discoveredPeripheralsDict[identifier] {
            connect(peripheral: cached)
            return
        }
        let peripherals = centralManager.retrievePeripherals(withIdentifiers: [identifier])
        guard let peripheral = peripherals.first else {
            print("Unable to retrieve trusted peripheral \(identifier)")
            return
        }
        discoveredPeripheralsDict[identifier] = peripheral
        connect(peripheral: peripheral)
    }

    func reconnectTrustedDevices(_ identifiers: [UUID]) {
        guard !identifiers.isEmpty else { return }
        for id in identifiers {
            reconnect(to: id)
        }
    }
}

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // If a scan was requested before Bluetooth was ready, start it now.
        guard central.state == .poweredOn else { return }
        guard pendingScanWhenPoweredOn else { return }
        pendingScanWhenPoweredOn = false
        startScanning()
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        _ = updateCachedName(from: advertisementData, for: peripheral)
        let name = cachedDisplayName(for: peripheral)
        
        print("Discovered peripheral: \(name)")
        print("Advertisement data: \(advertisementData)")
        print("RSSI: \(RSSI)")
        BluetoothLogManager.shared.logDiscovered(peripheral: peripheral, advertisementData: advertisementData, rssi: RSSI)

        // Keep a reference to the peripheral
        discoveredPeripheralsDict[peripheral.identifier] = peripheral

        // Prefer peripherals that explicitly advertise cycling-related services
        if let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            let hasCycling = serviceUUIDs.contains { BluetoothUUIDs.Service.allCycling.contains($0) }
            if hasCycling {
                // Notify delegate instead of auto-connecting
                delegate?.btDidDiscoverDevice(name: name, identifier: peripheral.identifier, rssi: RSSI.intValue, advertisementData: advertisementData)
            } else {
                print("Skipping non-cycling device: \(name)")
            }
        } else {
            // Some devices might not advertise services in the broad packet, but we might want them.
            // For now, adhere to strict filter to avoid noise, but maybe allow if name matches known devices?
            print("No service UUIDs in advertisement data for: \(name)")
            
            // Allow if name contains "Treadmill" or similar? For now, stick to UUID check as per original logic implies.
            // But if we want to be permissive:
            // delegate?.btDidDiscoverDevice(name: name, identifier: peripheral.identifier, rssi: RSSI.intValue, advertisementData: advertisementData)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let name = cachedDisplayName(for: peripheral)
        print("Connected to peripheral: \(name)")
        BluetoothLogManager.shared.logConnect(peripheral: peripheral)
        // Transition from connecting → connected
        if let idx = connectingPeripherals.firstIndex(of: peripheral) { connectingPeripherals.remove(at: idx) }
        if !connectedPeripherals.contains(peripheral) { connectedPeripherals.append(peripheral) }
        delegate?.btDidConnect(to: name)
        delegate?.btDidUpdateConnectedDevices(connectedPeripherals.map { cachedDisplayName(for: $0) })
        let deviceType = detectedDeviceTypes[peripheral.identifier] ?? .unknown
        delegate?.btDidConnectDevice(id: peripheral.identifier, name: name, deviceType: deviceType)
        // Discover the services we care about; then characteristics
        peripheral.delegate = self
        peripheral.discoverServices(BluetoothUUIDs.Service.allCycling)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect to peripheral: \(error?.localizedDescription ?? "Unknown error")")
        // Remove from in-flight connections so we can retry or scan again
        if let idx = connectingPeripherals.firstIndex(of: peripheral) { connectingPeripherals.remove(at: idx) }
        delegate?.btDidFailToConnect(name: cachedDisplayName(for: peripheral), error: error)
        // Restart scanning after a short delay only if allowed
        if allowAutoReconnect {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.startScanning() }
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let name = cachedDisplayName(for: peripheral)
        print("Disconnected from peripheral: \(name)")
        BluetoothLogManager.shared.logDisconnect(peripheral: peripheral, error: error)
        // Clean up state regardless of disconnect cause
        if let idx = connectedPeripherals.firstIndex(of: peripheral) { connectedPeripherals.remove(at: idx) }
        if let idx = connectingPeripherals.firstIndex(of: peripheral) { connectingPeripherals.remove(at: idx) }
        resetCSCState()
        delegate?.btDidDisconnect(name: name, error: error)
        delegate?.btDidUpdateConnectedDevices(connectedPeripherals.map { cachedDisplayName(for: $0) })
        // Resume scanning to allow reconnection only if allowed
        if allowAutoReconnect {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.startScanning() }
        }
    }
}

extension BluetoothManager: CBPeripheralDelegate {
    func peripheralDidUpdateName(_ peripheral: CBPeripheral) {
        // CoreBluetooth may populate `peripheral.name` only after we connect or later in the session.
        if let n = peripheral.name, !n.isEmpty {
            peripheralNameCache[peripheral.identifier] = n
            delegate?.btDidUpdateConnectedDevices(connectedPeripherals.map { cachedDisplayName(for: $0) })
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            print("Discovered service: \(service.uuid)")
            BluetoothLogManager.shared.logDidDiscoverService(service, peripheral: peripheral)
            // Ask CoreBluetooth for all characteristics; we will filter by UUID
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            print("Discovered characteristic: \(characteristic.uuid)")
            BluetoothLogManager.shared.logDidDiscoverCharacteristic(characteristic, service: service, peripheral: peripheral)
            if characteristic.uuid == BluetoothUUIDs.Characteristic.powerMeasurement ||
               characteristic.uuid == BluetoothUUIDs.Characteristic.cscMeasurement ||
               characteristic.uuid == BluetoothUUIDs.Characteristic.indoorBikeData ||
               characteristic.uuid == BluetoothUUIDs.Characteristic.treadmillData ||
               characteristic.uuid == BluetoothUUIDs.Characteristic.rowerData {
                // Subscribe to notifications for streaming sensor data
                peripheral.setNotifyValue(true, for: characteristic)
                BluetoothLogManager.shared.logNotifySet(true, characteristic: characteristic, peripheral: peripheral)

                // Detect device type based on which characteristic we're subscribing to
                let detected: FitnessDeviceType?
                switch characteristic.uuid {
                case BluetoothUUIDs.Characteristic.indoorBikeData: detected = .bike
                case BluetoothUUIDs.Characteristic.treadmillData: detected = .treadmill
                case BluetoothUUIDs.Characteristic.rowerData: detected = .rower
                default: detected = nil
                }
                if let detected {
                    detectedDeviceTypes[peripheral.identifier] = detected
                    delegate?.btDidDetectDeviceType(detected)
                    // Characteristic discovery happens after didConnect, so the connect
                    // event carried .unknown. Re-emit it now that the type is known so
                    // trusted-device and compatibility records get the real type.
                    delegate?.btDidConnectDevice(
                        id: peripheral.identifier,
                        name: cachedDisplayName(for: peripheral),
                        deviceType: detected
                    )
                }
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        print("Received data from characteristic: \(characteristic.uuid)")
        BluetoothLogManager.shared.logRX(data, characteristic: characteristic, peripheral: peripheral, error: error)
        if characteristic.uuid == BluetoothUUIDs.Characteristic.powerMeasurement {
            if let watts = CyclingSensorParser.parsePowerMeasurement(data) {
                delegate?.btDidUpdatePower(watts: watts)
            }
        } else if characteristic.uuid == BluetoothUUIDs.Characteristic.cscMeasurement {
            // Parse CSC and compute crank cadence (RPM).
            let csc = CyclingSensorParser.parseCSC(data)
            delegate?.btDidUpdateCSC(wheelRev: csc.wheelRev, wheelTime: csc.wheelTime, crankRev: csc.crankRev, crankTime: csc.crankTime)
            guard let count = csc.crankRev, let time = csc.crankTime else { return }
            if let rpm = CyclingSensorParser.computeCadenceRPM(previousCount: cscLastCrankCount, previousTime: cscLastCrankTime, currentCount: count, currentTime: time) {
                delegate?.btDidUpdateCadence(rpm: rpm)
            }
            cscLastCrankCount = count
            cscLastCrankTime = time
        } else if characteristic.uuid == BluetoothUUIDs.Characteristic.indoorBikeData {
            let bikeData = CyclingSensorParser.parseIndoorBikeData(data)
            if let watts = bikeData.instantaneousPowerWatts { delegate?.btDidUpdatePower(watts: watts) }
            if let rpm = bikeData.instantaneousCadenceRpm { delegate?.btDidUpdateCadence(rpm: rpm) }
            if let mps = bikeData.instantaneousSpeedMps { delegate?.btDidUpdateSpeed(mps: mps) }
            if let meters = bikeData.totalDistanceMeters { delegate?.btDidUpdateTotalDistance(meters: meters) }
            delegate?.btDidUpdateIndoorBike(bikeData)
        } else if characteristic.uuid == BluetoothUUIDs.Characteristic.treadmillData {
            let treadmill = TreadmillSensorParser.parseTreadmillData(data)
            if let mps = treadmill.instantaneousSpeedMps { delegate?.btDidUpdateSpeed(mps: mps) }
            if let meters = treadmill.totalDistanceMeters { delegate?.btDidUpdateTotalDistance(meters: meters) }
            delegate?.btDidUpdateTreadmill(treadmill)
        } else if characteristic.uuid == BluetoothUUIDs.Characteristic.rowerData {
            let rower = RowerSensorParser.parseRowerData(data)
            if let watts = rower.instantaneousPowerWatts { delegate?.btDidUpdatePower(watts: watts) }
            if let meters = rower.totalDistanceMeters { delegate?.btDidUpdateTotalDistance(meters: meters) }
            delegate?.btDidUpdateRower(rower)
        }
    }
    
}



