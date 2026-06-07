import Foundation

struct EquipmentCompatibilityRecord: Codable, Identifiable, Hashable {
    let id: UUID
    var deviceName: String
    var deviceType: FitnessDeviceType
    var firstConnectedAt: Date
    var lastConnectedAt: Date
    var successfulWorkoutCount: Int
    var notes: String

    init(
        id: UUID = UUID(),
        deviceName: String,
        deviceType: FitnessDeviceType,
        firstConnectedAt: Date = Date(),
        lastConnectedAt: Date = Date(),
        successfulWorkoutCount: Int = 0,
        notes: String = ""
    ) {
        self.id = id
        self.deviceName = deviceName
        self.deviceType = deviceType
        self.firstConnectedAt = firstConnectedAt
        self.lastConnectedAt = lastConnectedAt
        self.successfulWorkoutCount = successfulWorkoutCount
        self.notes = notes
    }
}

enum CompatibilityStore {
    private static let storageKey = "equipmentCompatibilityRecords"

    static func loadAll() -> [EquipmentCompatibilityRecord] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let records = try? JSONDecoder().decode([EquipmentCompatibilityRecord].self, from: data) else {
            return []
        }
        return records.sorted { $0.lastConnectedAt > $1.lastConnectedAt }
    }

    static func recordSuccessfulConnection(name: String, deviceType: FitnessDeviceType) {
        var records = loadAll()
        if let index = records.firstIndex(where: { $0.deviceName == name && $0.deviceType == deviceType }) {
            records[index].lastConnectedAt = Date()
        } else {
            records.append(EquipmentCompatibilityRecord(deviceName: name, deviceType: deviceType))
        }
        save(records)
    }

    static func recordSuccessfulWorkout(name: String, deviceType: FitnessDeviceType) {
        var records = loadAll()
        if let index = records.firstIndex(where: { $0.deviceName == name && $0.deviceType == deviceType }) {
            records[index].lastConnectedAt = Date()
            records[index].successfulWorkoutCount += 1
        } else {
            var record = EquipmentCompatibilityRecord(deviceName: name, deviceType: deviceType)
            record.successfulWorkoutCount = 1
            records.append(record)
        }
        save(records)
    }

    static func testedDeviceNames() -> [String] {
        loadAll().map(\.deviceName)
    }

    private static func save(_ records: [EquipmentCompatibilityRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
