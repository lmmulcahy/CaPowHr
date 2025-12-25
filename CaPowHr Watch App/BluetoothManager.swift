import Foundation
import CoreBluetooth

// MARK: - BluetoothManager & Delegate
//
// This file encapsulates the watchOS CoreBluetooth flow for cycling sensors.
// Responsibilities:
// - Run a two-phase scan (broad → filtered) to discover peripherals
// - Connect to peripherals advertising cycling services (CSC, FTMS, Cycling Power)
// - Maintain connection state to avoid duplicate connections and to keep peripherals alive
// - Discover characteristics and subscribe (notifications) for data streams
// - Route raw data to SensorDataParser and emit updates to the app via delegate callbacks
//
// Notes on watchOS/CoreBluetooth behavior that inform the design:
// - You must keep a strong reference to CBPeripheral while connecting/connected to avoid API MISUSE
// - Scanning while connecting can delay or interfere with connections; we stop scanning before connect
// - Some peripherals rotate advertisements; we disable duplicates to reduce log spam

/// Delegate for receiving device lifecycle events and parsed sensor updates.
/// Implemented by higher-level coordinators (e.g., WorkoutManager).
protocol BluetoothManagerDelegate: AnyObject {
    /// Called when we discover a peripheral that advertises cycling services.
    func btDidDiscoverCyclingDevice(name: String)
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
    /// Emitted whenever the set of connected devices changes.
    func btDidUpdateConnectedDevices(_ names: [String])
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
    /// Controls whether the manager should automatically resume scanning after disconnect/fail.
    private var allowAutoReconnect: Bool = true

    // UUIDs
    private let cyclingPowerServiceUUID = CBUUID(string: "1818")   // Cycling Power Service
    private let cyclingSpeedCadenceServiceUUID = CBUUID(string: "1816") // CSC Service
    private let powerMeasurementCharacteristicUUID = CBUUID(string: "2A63") // Cycling Power Meas.
    private let cscMeasurementCharacteristicUUID = CBUUID(string: "2A5B")   // CSC Meas.
    private let ftmsServiceUUID = CBUUID(string: "1826")            // Fitness Machine Service
    private let ftmsDataCharacteristicUUID = CBUUID(string: "2AD2") // Indoor Bike Data

    // CSC cadence tracking (for wrap-safe cadence deltas)
    private var cscLastCrankTime: UInt16 = 0
    private var cscLastCrankCount: UInt16 = 0

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
            print("Bluetooth not powered on, state: \(centralManager.state.rawValue)")
            return
        }
        // User explicitly began scanning; allow auto-reconnect behavior going forward
        allowAutoReconnect = true
        isScanning = true
        print("Starting Bluetooth scan for cycling services...")
        BluetoothLogManager.shared.logScanStart()
        // Phase 1: broad scan for any peripheral (no service filter)
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        // After a short window, narrow to cycling services to reduce noise
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self else { return }
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

    /// Stop scanning if active to conserve power and reduce radio contention.
    func stopScanning() {
        if !isScanning { return }
        isScanning = false
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
        delegate?.btDidUpdateConnectedDevices([])
    }
}

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // handled in startScanning guard
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print("Discovered peripheral: \(peripheral.name ?? "Unknown")")
        print("Advertisement data: \(advertisementData)")
        print("RSSI: \(RSSI)")
        BluetoothLogManager.shared.logDiscovered(peripheral: peripheral, advertisementData: advertisementData, rssi: RSSI)

        // Prefer peripherals that explicitly advertise cycling-related services
        if let serviceUUIDs = advertisementData["kCBAdvDataServiceUUIDs"] as? [CBUUID] {
            let hasCycling = serviceUUIDs.contains { $0 == cyclingPowerServiceUUID || $0 == cyclingSpeedCadenceServiceUUID || $0 == ftmsServiceUUID }
            if hasCycling {
                let name = peripheral.name ?? "Unknown"
                delegate?.btDidDiscoverCyclingDevice(name: name)
                // Skip if already connected or connection is in-flight
                if !connectedPeripherals.contains(peripheral) && !connectingPeripherals.contains(peripheral) {
                    // Stop scanning to prevent radio contention during connection
                    stopScanning()
                    connectingPeripherals.append(peripheral)
                    print("Connecting to \(name)...")
                    central.connect(peripheral, options: nil)
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
        BluetoothLogManager.shared.logConnect(peripheral: peripheral)
        // Transition from connecting → connected
        if let idx = connectingPeripherals.firstIndex(of: peripheral) { connectingPeripherals.remove(at: idx) }
        if !connectedPeripherals.contains(peripheral) { connectedPeripherals.append(peripheral) }
        delegate?.btDidConnect(to: peripheral.name ?? "Unknown")
        delegate?.btDidUpdateConnectedDevices(connectedPeripherals.map { $0.name ?? "Unknown Device" })
        // Discover the services we care about; then characteristics
        peripheral.delegate = self
        peripheral.discoverServices([cyclingPowerServiceUUID, cyclingSpeedCadenceServiceUUID, ftmsServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect to peripheral: \(error?.localizedDescription ?? "Unknown error")")
        // Remove from in-flight connections so we can retry or scan again
        if let idx = connectingPeripherals.firstIndex(of: peripheral) { connectingPeripherals.remove(at: idx) }
        delegate?.btDidFailToConnect(name: peripheral.name ?? "Unknown", error: error)
        // Restart scanning after a short delay only if allowed
        if allowAutoReconnect {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.startScanning() }
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected from peripheral: \(peripheral.name ?? "Unknown")")
        BluetoothLogManager.shared.logDisconnect(peripheral: peripheral, error: error)
        // Clean up state regardless of disconnect cause
        if let idx = connectedPeripherals.firstIndex(of: peripheral) { connectedPeripherals.remove(at: idx) }
        if let idx = connectingPeripherals.firstIndex(of: peripheral) { connectingPeripherals.remove(at: idx) }
        delegate?.btDidDisconnect(name: peripheral.name ?? "Unknown", error: error)
        delegate?.btDidUpdateConnectedDevices(connectedPeripherals.map { $0.name ?? "Unknown Device" })
        // Resume scanning to allow reconnection only if allowed
        if allowAutoReconnect {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.startScanning() }
        }
    }
}

extension BluetoothManager: CBPeripheralDelegate {
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
            if characteristic.uuid == powerMeasurementCharacteristicUUID ||
               characteristic.uuid == cscMeasurementCharacteristicUUID ||
               characteristic.uuid == ftmsDataCharacteristicUUID {
                // Subscribe to notifications for streaming sensor data
                peripheral.setNotifyValue(true, for: characteristic)
                BluetoothLogManager.shared.logNotifySet(true, characteristic: characteristic, peripheral: peripheral)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        print("Received data from characteristic: \(characteristic.uuid)")
        BluetoothLogManager.shared.logRX(data, characteristic: characteristic, peripheral: peripheral, error: error)
        if characteristic.uuid == powerMeasurementCharacteristicUUID {
            if let watts = SensorDataParser.parsePowerMeasurement(data) {
                delegate?.btDidUpdatePower(watts: watts)
            }
        } else if characteristic.uuid == cscMeasurementCharacteristicUUID {
            // Parse minimal CSC crank data (flags + count/time) then compute RPM
            guard data.count >= 1 else { return }
            let flags = data[0]
            var offset = 1
            if (flags & 0x01) != 0 { // wheel present, skip 6 bytes
                guard data.count >= offset + 6 else { return }
                offset += 6
            }
            guard (flags & 0x02) != 0, data.count >= offset + 4 else { return }
            let count = data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: UInt16.self) }
            let time = data.subdata(in: (offset + 2)..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt16.self) }
            if let rpm = SensorDataParser.computeCadenceRPM(previousCount: cscLastCrankCount, previousTime: cscLastCrankTime, currentCount: count, currentTime: time) {
                delegate?.btDidUpdateCadence(rpm: rpm)
            }
            cscLastCrankCount = count
            cscLastCrankTime = time
        } else if characteristic.uuid == ftmsDataCharacteristicUUID {
            let ftms = SensorDataParser.parseFTMS(data)
            if let watts = ftms.instantaneousPowerWatts { delegate?.btDidUpdatePower(watts: watts) }
            if let rpm = ftms.instantaneousCadenceRpm { delegate?.btDidUpdateCadence(rpm: rpm) }
            if let mps = ftms.instantaneousSpeedMps { delegate?.btDidUpdateSpeed(mps: mps) }
            if let meters = ftms.totalDistanceMeters { delegate?.btDidUpdateTotalDistance(meters: meters) }
        }
    }
    
}



