import Foundation

struct TrustedDevice: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var deviceType: FitnessDeviceType
    var lastConnectedAt: Date

    init(id: UUID, name: String, deviceType: FitnessDeviceType = .unknown, lastConnectedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.deviceType = deviceType
        self.lastConnectedAt = lastConnectedAt
    }
}

extension FitnessDeviceType: Codable {}

enum TrustedDeviceStore {
    private static let storageKey = "trustedBLEDevices"

    static func loadAll() -> [TrustedDevice] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let devices = try? JSONDecoder().decode([TrustedDevice].self, from: data) else {
            return []
        }
        return devices.sorted { $0.lastConnectedAt > $1.lastConnectedAt }
    }

    static func remember(id: UUID, name: String, deviceType: FitnessDeviceType) {
        var devices = loadAll()
        if let index = devices.firstIndex(where: { $0.id == id }) {
            devices[index].name = name
            // Type detection lags the connect event; don't downgrade a known
            // type when a pre-detection event reports .unknown.
            if deviceType != .unknown {
                devices[index].deviceType = deviceType
            }
            devices[index].lastConnectedAt = Date()
        } else {
            devices.append(TrustedDevice(id: id, name: name, deviceType: deviceType))
        }
        save(devices)
    }

    static func forget(id: UUID) {
        var devices = loadAll()
        devices.removeAll { $0.id == id }
        save(devices)
    }

    static func mostRecent() -> TrustedDevice? {
        loadAll().first
    }

    private static func save(_ devices: [TrustedDevice]) {
        guard let data = try? JSONEncoder().encode(devices) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
