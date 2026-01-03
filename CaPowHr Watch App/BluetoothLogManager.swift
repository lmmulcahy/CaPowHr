import Foundation
import CoreBluetooth

// MARK: - BluetoothLogManager
//
// Records all BLE activity (scan/discovery/connect/notify/RX/TX) into a per-session log file.
// Format: JSON Lines (one JSON object per line) for easy grepping and sharing in GitHub issues.
//
// Files are written under Documents/BLELogs/ and can be exported via ShareLink in the UI.

final class BluetoothLogManager: ObservableObject {
    static let shared = BluetoothLogManager()

    @Published private(set) var isLogging: Bool = false
    @Published private(set) var currentLogFileURL: URL?
    @Published private(set) var latestLogFileURL: URL?
    @Published private(set) var lastErrorMessage: String?

    private let queue = DispatchQueue(label: "com.capowhr.bluetoothlog")
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private var fileHandle: FileHandle?

    private init() {
        latestLogFileURL = Self.findLatestLogFileURL()
    }

    /// Loads the latest log file as UTF-8 text, truncating from the front if needed.
    /// Intended for embedding into a GitHub issue body.
    func loadLatestLogText(maxBytes: Int = 45_000) -> (text: String, wasTruncated: Bool, filename: String)? {
        guard let url = latestLogFileURL else { return nil }
        return Self.loadLogText(from: url, maxBytes: maxBytes)
    }

    static func loadLogText(from url: URL, maxBytes: Int = 45_000) -> (text: String, wasTruncated: Bool, filename: String)? {
        do {
            var data = try Data(contentsOf: url)
            let filename = url.lastPathComponent

            var wasTruncated = false
            if data.count > maxBytes {
                wasTruncated = true
                let tailSlice = data.suffix(maxBytes)
                data = Data(tailSlice)

                // Try to start on a newline boundary (JSONL), so the first line isn't half-record.
                if let firstNewline = data.firstIndex(of: 0x0A) {
                    let start = data.index(after: firstNewline)
                    if start < data.endIndex {
                        data = data.subdata(in: start..<data.endIndex)
                    }
                }
            }

            let text = String(decoding: data, as: UTF8.self)
            return (text: text, wasTruncated: wasTruncated, filename: filename)
        } catch {
            return nil
        }
    }

    func startSession(reason: String, appContext: [String: String] = [:]) {
        queue.async {
            if self.isLogging { return }
            do {
                let dir = try Self.ensureLogsDirectory()
                let ts = Self.filenameTimestamp(Date())
                let filename = "ble-session-\(ts).jsonl"
                let url = dir.appendingPathComponent(filename)

                FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil)
                let fh = try FileHandle(forWritingTo: url)
                self.fileHandle = fh

                DispatchQueue.main.async {
                    self.currentLogFileURL = url
                    self.latestLogFileURL = url
                    self.isLogging = true
                    self.lastErrorMessage = nil
                }

                // Header record: session metadata.
                let header = BLELogRecord(type: .sessionStart, message: "Session start", reason: reason, app: appContext)
                try self.writeRecord(header)
            } catch {
                DispatchQueue.main.async {
                    self.lastErrorMessage = "BLE logging start failed: \(error.localizedDescription)"
                    self.isLogging = false
                    self.currentLogFileURL = nil
                }
                self.fileHandle = nil
            }
        }
    }

    func endSession(reason: String) {
        queue.async {
            if !self.isLogging { return }
            do {
                let footer = BLELogRecord(type: .sessionEnd, message: "Session end", reason: reason)
                try self.writeRecord(footer)
            } catch {
                DispatchQueue.main.async {
                    self.lastErrorMessage = "BLE logging end failed: \(error.localizedDescription)"
                }
            }

            do { try self.fileHandle?.close() } catch { /* ignore */ }
            self.fileHandle = nil
            DispatchQueue.main.async {
                self.isLogging = false
                self.currentLogFileURL = nil
            }
        }
    }

    func logScanStart() { logSimple(.scanStart, "Scan start") }
    func logScanStop() { logSimple(.scanStop, "Scan stop") }

    func logDiscovered(peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        queue.async {
            guard self.isLogging else { return }
            let adv = Self.stringifyAdvertisement(advertisementData)
            let rec = BLELogRecord(
                type: .discover,
                message: "Discovered peripheral",
                peripheral: BLEPeripheralRef(from: peripheral),
                rssi: rssi.intValue,
                advertisement: adv
            )
            try? self.writeRecord(rec)
        }
    }

    func logConnect(peripheral: CBPeripheral) {
        logWithPeripheral(.connect, "Connected", peripheral: peripheral)
    }

    func logDisconnect(peripheral: CBPeripheral, error: Error?) {
        let msg = error.map { "Disconnected: \($0.localizedDescription)" } ?? "Disconnected"
        logWithPeripheral(.disconnect, msg, peripheral: peripheral)
    }

    func logDidDiscoverService(_ service: CBService, peripheral: CBPeripheral) {
        queue.async {
            guard self.isLogging else { return }
            let rec = BLELogRecord(
                type: .serviceDiscovered,
                message: "Discovered service",
                peripheral: BLEPeripheralRef(from: peripheral),
                serviceUUID: service.uuid.uuidString
            )
            try? self.writeRecord(rec)
        }
    }

    func logDidDiscoverCharacteristic(_ characteristic: CBCharacteristic, service: CBService, peripheral: CBPeripheral) {
        queue.async {
            guard self.isLogging else { return }
            let rec = BLELogRecord(
                type: .characteristicDiscovered,
                message: "Discovered characteristic",
                peripheral: BLEPeripheralRef(from: peripheral),
                serviceUUID: service.uuid.uuidString,
                characteristicUUID: characteristic.uuid.uuidString
            )
            try? self.writeRecord(rec)
        }
    }

    func logNotifySet(_ enabled: Bool, characteristic: CBCharacteristic, peripheral: CBPeripheral) {
        queue.async {
            guard self.isLogging else { return }
            let rec = BLELogRecord(
                type: .notifySet,
                message: enabled ? "Notify enabled" : "Notify disabled",
                peripheral: BLEPeripheralRef(from: peripheral),
                serviceUUID: characteristic.service?.uuid.uuidString,
                characteristicUUID: characteristic.uuid.uuidString
            )
            try? self.writeRecord(rec)
        }
    }

    func logRX(_ data: Data, characteristic: CBCharacteristic, peripheral: CBPeripheral, error: Error?) {
        queue.async {
            guard self.isLogging else { return }
            let msg = error.map { "RX error: \($0.localizedDescription)" } ?? "RX"
            let rec = BLELogRecord(
                type: .rx,
                message: msg,
                peripheral: BLEPeripheralRef(from: peripheral),
                serviceUUID: characteristic.service?.uuid.uuidString,
                characteristicUUID: characteristic.uuid.uuidString,
                dataHex: data.hexString
            )
            try? self.writeRecord(rec)
        }
    }

    func logTX(_ data: Data, characteristic: CBCharacteristic, peripheral: CBPeripheral) {
        queue.async {
            guard self.isLogging else { return }
            let rec = BLELogRecord(
                type: .tx,
                message: "TX",
                peripheral: BLEPeripheralRef(from: peripheral),
                serviceUUID: characteristic.service?.uuid.uuidString,
                characteristicUUID: characteristic.uuid.uuidString,
                dataHex: data.hexString
            )
            try? self.writeRecord(rec)
        }
    }

    // MARK: - Internals

    private func logSimple(_ type: BLELogRecord.RecordType, _ message: String) {
        queue.async {
            guard self.isLogging else { return }
            let rec = BLELogRecord(type: type, message: message)
            try? self.writeRecord(rec)
        }
    }

    private func logWithPeripheral(_ type: BLELogRecord.RecordType, _ message: String, peripheral: CBPeripheral) {
        queue.async {
            guard self.isLogging else { return }
            let rec = BLELogRecord(type: type, message: message, peripheral: BLEPeripheralRef(from: peripheral))
            try? self.writeRecord(rec)
        }
    }

    private func writeRecord(_ record: BLELogRecord) throws {
        guard let fh = fileHandle else { return }
        let data = try encoder.encode(record)
        fh.write(data)
        fh.write(Data([0x0A])) // newline
    }

    private static func ensureLogsDirectory() throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("BLELogs", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func filenameTimestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HHmmss'Z'"
        return f.string(from: date)
    }

    private static func findLatestLogFileURL() -> URL? {
        do {
            let dir = try ensureLogsDirectory()
            let urls = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
            return urls
                .filter { $0.pathExtension.lowercased() == "jsonl" }
                .sorted(by: { (a, b) -> Bool in
                    let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    return da > db
                })
                .first
        } catch {
            return nil
        }
    }

    private static func stringifyAdvertisement(_ advertisementData: [String: Any]) -> [String: String] {
        // Keep this intentionally lossy + stringy: it’s for debugging and GitHub issues, not rehydration.
        var out: [String: String] = [:]
        for (k, v) in advertisementData {
            if let uuids = v as? [CBUUID] {
                out[k] = uuids.map { $0.uuidString }.joined(separator: ",")
            } else if let n = v as? NSNumber {
                out[k] = n.stringValue
            } else if let s = v as? String {
                out[k] = s
            } else if let d = v as? Data {
                out[k] = d.hexString
            } else {
                out[k] = String(describing: v)
            }
        }
        return out
    }
}

struct BLEPeripheralRef: Codable {
    var name: String?
    var identifier: String

    init(from peripheral: CBPeripheral) {
        self.name = peripheral.name
        self.identifier = peripheral.identifier.uuidString
    }
}

struct BLELogRecord: Codable {
    enum RecordType: String, Codable {
        case sessionStart
        case sessionEnd
        case scanStart
        case scanStop
        case discover
        case connect
        case disconnect
        case serviceDiscovered
        case characteristicDiscovered
        case notifySet
        case rx
        case tx
    }

    var ts: Date
    var type: RecordType
    var message: String

    var reason: String?
    var peripheral: BLEPeripheralRef?
    var serviceUUID: String?
    var characteristicUUID: String?
    var rssi: Int?
    var dataHex: String?
    var advertisement: [String: String]?

    // Optional app context (version/build/etc) included only in session start.
    var app: [String: String]?

    /// Convenience initializer with defaults for optional fields.
    init(
        type: RecordType,
        message: String,
        reason: String? = nil,
        peripheral: BLEPeripheralRef? = nil,
        serviceUUID: String? = nil,
        characteristicUUID: String? = nil,
        rssi: Int? = nil,
        dataHex: String? = nil,
        advertisement: [String: String]? = nil,
        app: [String: String]? = nil
    ) {
        self.ts = Date()
        self.type = type
        self.message = message
        self.reason = reason
        self.peripheral = peripheral
        self.serviceUUID = serviceUUID
        self.characteristicUUID = characteristicUUID
        self.rssi = rssi
        self.dataHex = dataHex
        self.advertisement = advertisement
        self.app = app
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}


