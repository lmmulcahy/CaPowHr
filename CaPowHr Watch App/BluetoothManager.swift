import Foundation
import CoreBluetooth

protocol BluetoothManagerDelegate: AnyObject {
    func btDidDiscoverCyclingDevice(name: String)
    func btDidConnect(to name: String)
    func btDidFailToConnect(name: String, error: Error?)
    func btDidDisconnect(name: String, error: Error?)
    func btDidUpdatePower(watts: Double)
    func btDidUpdateCadence(rpm: Double)
    func btDidUpdateSpeed(mps: Double)
    func btDidUpdateTotalDistance(meters: Double)
    func btDidUpdateConnectedDevices(_ names: [String])
}

final class BluetoothManager: NSObject {
    weak var delegate: BluetoothManagerDelegate?

    private var centralManager: CBCentralManager!
    private(set) var isScanning: Bool = false

    private var connectedPeripherals: [CBPeripheral] = []
    private var connectingPeripherals: [CBPeripheral] = []

    // UUIDs
    private let cyclingPowerServiceUUID = CBUUID(string: "1818")
    private let cyclingSpeedCadenceServiceUUID = CBUUID(string: "1816")
    private let powerMeasurementCharacteristicUUID = CBUUID(string: "2A63")
    private let cscMeasurementCharacteristicUUID = CBUUID(string: "2A5B")
    private let ftmsServiceUUID = CBUUID(string: "1826")
    private let ftmsDataCharacteristicUUID = CBUUID(string: "2AD2")

    // CSC cadence tracking
    private var cscLastCrankTime: UInt16 = 0
    private var cscLastCrankCount: UInt16 = 0

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func startScanning() {
        if isScanning { return }
        guard centralManager.state == .poweredOn else {
            print("Bluetooth not powered on, state: \(centralManager.state.rawValue)")
            return
        }
        isScanning = true
        print("Starting Bluetooth scan for cycling services...")
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self else { return }
            if self.isScanning {
                print("Switching to specific service scanning...")
                self.centralManager.stopScan()
                self.centralManager.scanForPeripherals(withServices: [self.cyclingPowerServiceUUID, self.cyclingSpeedCadenceServiceUUID, self.ftmsServiceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
            }
        }
    }

    func stopScanning() {
        if !isScanning { return }
        isScanning = false
        print("Stopping Bluetooth scan...")
        centralManager.stopScan()
    }

    func disconnectAll() {
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

        if let serviceUUIDs = advertisementData["kCBAdvDataServiceUUIDs"] as? [CBUUID] {
            let hasCycling = serviceUUIDs.contains { $0 == cyclingPowerServiceUUID || $0 == cyclingSpeedCadenceServiceUUID || $0 == ftmsServiceUUID }
            if hasCycling {
                let name = peripheral.name ?? "Unknown"
                delegate?.btDidDiscoverCyclingDevice(name: name)
                if !connectedPeripherals.contains(peripheral) && !connectingPeripherals.contains(peripheral) {
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
        if let idx = connectingPeripherals.firstIndex(of: peripheral) { connectingPeripherals.remove(at: idx) }
        if !connectedPeripherals.contains(peripheral) { connectedPeripherals.append(peripheral) }
        delegate?.btDidConnect(to: peripheral.name ?? "Unknown")
        delegate?.btDidUpdateConnectedDevices(connectedPeripherals.map { $0.name ?? "Unknown Device" })
        peripheral.delegate = self
        peripheral.discoverServices([cyclingPowerServiceUUID, cyclingSpeedCadenceServiceUUID, ftmsServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect to peripheral: \(error?.localizedDescription ?? "Unknown error")")
        if let idx = connectingPeripherals.firstIndex(of: peripheral) { connectingPeripherals.remove(at: idx) }
        delegate?.btDidFailToConnect(name: peripheral.name ?? "Unknown", error: error)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.startScanning() }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected from peripheral: \(peripheral.name ?? "Unknown")")
        if let idx = connectedPeripherals.firstIndex(of: peripheral) { connectedPeripherals.remove(at: idx) }
        if let idx = connectingPeripherals.firstIndex(of: peripheral) { connectingPeripherals.remove(at: idx) }
        delegate?.btDidDisconnect(name: peripheral.name ?? "Unknown", error: error)
        delegate?.btDidUpdateConnectedDevices(connectedPeripherals.map { $0.name ?? "Unknown Device" })
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.startScanning() }
    }
}

extension BluetoothManager: CBPeripheralDelegate {
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
            if characteristic.uuid == powerMeasurementCharacteristicUUID ||
               characteristic.uuid == cscMeasurementCharacteristicUUID ||
               characteristic.uuid == ftmsDataCharacteristicUUID {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        print("Received data from characteristic: \(characteristic.uuid)")
        if characteristic.uuid == powerMeasurementCharacteristicUUID {
            parsePowerData(data)
        } else if characteristic.uuid == cscMeasurementCharacteristicUUID {
            parseCadenceData(data)
        } else if characteristic.uuid == ftmsDataCharacteristicUUID {
            parseFTMSData(data)
        }
    }

    private func parsePowerData(_ data: Data) {
        guard data.count >= 2 else { return }
        let power = data.subdata(in: 0..<2).withUnsafeBytes { $0.load(as: UInt16.self) }
        delegate?.btDidUpdatePower(watts: Double(power))
    }

    private func parseCadenceData(_ data: Data) {
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
        if cscLastCrankCount != 0 {
            let revDelta = UInt16(bitPattern: Int16(bitPattern: count) &- Int16(bitPattern: cscLastCrankCount))
            let timeDelta = UInt16(bitPattern: Int16(bitPattern: time) &- Int16(bitPattern: cscLastCrankTime))
            let dtTicks = Int(timeDelta)
            if dtTicks > 0 {
                let seconds = Double(dtTicks) / 1024.0
                let rpm = (Double(revDelta) / seconds) * 60.0
                delegate?.btDidUpdateCadence(rpm: rpm)
            }
        }
        cscLastCrankCount = count
        cscLastCrankTime = time
    }

    private func parseFTMSData(_ data: Data) {
        guard data.count >= 2 else { return }
        let flags = UInt16(data[0]) | (UInt16(data[1]) << 8)
        var offset = 2
        func readUInt16() -> UInt16? { guard data.count >= offset + 2 else { return nil }; defer { offset += 2 }; return data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: UInt16.self) } }
        func readInt16() -> Int16? { guard data.count >= offset + 2 else { return nil }; defer { offset += 2 }; return data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: Int16.self) } }
        func readUInt8() -> UInt8? { guard data.count > offset else { return nil }; defer { offset += 1 }; return data[offset] }
        func readUInt24() -> UInt32? { guard data.count >= offset + 3 else { return nil }; let b0 = UInt32(data[offset]); let b1 = UInt32(data[offset+1]); let b2 = UInt32(data[offset+2]); offset += 3; return b0 | (b1 << 8) | (b2 << 16) }

        if (flags & 0x0002) != 0, let instSpeedRaw = readUInt16() {
            let speedMps = Double(instSpeedRaw) / 100.0
            delegate?.btDidUpdateSpeed(mps: speedMps)
        }
        if (flags & 0x0004) != 0 { _ = readUInt16() }
        if (flags & 0x0008) != 0, let cadenceHalf = readUInt16() {
            delegate?.btDidUpdateCadence(rpm: Double(cadenceHalf) / 2.0)
        }
        if (flags & 0x0010) != 0 { _ = readUInt16() }
        if (flags & 0x0020) != 0, let totalDistance = readUInt24() {
            delegate?.btDidUpdateTotalDistance(meters: Double(totalDistance))
        }
        if (flags & 0x0040) != 0 { _ = readInt16() }
        if (flags & 0x0080) != 0, let instPower = readInt16() {
            delegate?.btDidUpdatePower(watts: Double(instPower))
        }
        if (flags & 0x0100) != 0 { _ = readInt16() }
        if (flags & 0x0200) != 0 { _ = readUInt16() }
        if (flags & 0x0400) != 0 { _ = readUInt16() }
        if (flags & 0x0800) != 0 { _ = readUInt8() }
        if (flags & 0x1000) != 0 { _ = readUInt8() }
        if (flags & 0x2000) != 0 { _ = readUInt8() }
        if (flags & 0x4000) != 0 { _ = readUInt16() }
        if (flags & 0x8000) != 0 { _ = readUInt16() }
    }
}


