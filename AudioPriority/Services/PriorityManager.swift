import Foundation

public struct StoredDevice: Codable, Equatable {
    public let uid: String
    public let name: String
    public let isInput: Bool
    public var lastSeen: Date

    public init(uid: String, name: String, isInput: Bool, lastSeen: Date) {
        self.uid = uid
        self.name = name
        self.isInput = isInput
        self.lastSeen = lastSeen
    }

    public var lastSeenRelative: String {
        let now = Date()
        let interval = now.timeIntervalSince(lastSeen)

        if interval < 60 {
            return "now"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        } else if interval < 2592000 {
            let weeks = Int(interval / 604800)
            return "\(weeks)w ago"
        } else {
            let months = Int(interval / 2592000)
            return "\(months)mo ago"
        }
    }
}

public class PriorityManager {
    private let defaults: UserDefaults

    private let inputPrioritiesKey = "inputPriorities"
    private let outputPrioritiesKey = "speakerPriorities"
    private let customModeKey = "customMode"
    private let knownDevicesKey = "knownDevices"
    private let knownDevicesDedupedKey = "knownDevicesDeduped"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Known Devices (Persistent Memory)

    public func getKnownDevices() -> [StoredDevice] {
        guard let data = defaults.data(forKey: knownDevicesKey) else {
            return []
        }
        guard let devices = try? JSONDecoder().decode([StoredDevice].self, from: data) else {
            // Preserve the raw data to avoid silent data loss.
            return []
        }

        var normalized = devices
        if !defaults.bool(forKey: knownDevicesDedupedKey) {
            normalized = dedupeKnownDevices(normalized)
        }
        normalized = sortKnownDevices(normalized)

        if normalized != devices {
            saveKnownDevices(normalized)
        }
        defaults.set(true, forKey: knownDevicesDedupedKey)
        return normalized
    }

    public func rememberDevice(_ uid: String, name: String, isInput: Bool) {
        updateKnownDevices([StoredDevice(uid: uid, name: name, isInput: isInput, lastSeen: Date())])
    }

    public func rememberDevices(_ devices: [AudioDevice]) {
        let now = Date()
        let updates = devices.map { device in
            StoredDevice(uid: device.uid, name: device.name, isInput: device.type == .input, lastSeen: now)
        }
        updateKnownDevices(updates)
    }

    public func forgetDevice(_ uid: String) {
        var known = getKnownDevices()
        known.removeAll { $0.uid == uid }
        saveKnownDevices(sortKnownDevices(known))
    }

    public func forgetDevice(_ uid: String, isInput: Bool) {
        var known = getKnownDevices()
        known.removeAll { $0.uid == uid && $0.isInput == isInput }
        saveKnownDevices(sortKnownDevices(known))
    }

    private func saveKnownDevices(_ devices: [StoredDevice]) {
        if let data = try? JSONEncoder().encode(devices) {
            defaults.set(data, forKey: knownDevicesKey)
        }
    }

    private func updateKnownDevices(_ updates: [StoredDevice]) {
        guard !updates.isEmpty else { return }
        var known = getKnownDevices()
        var indexByKey: [String: Int] = [:]
        for (index, device) in known.enumerated() {
            indexByKey[key(for: device.uid, isInput: device.isInput)] = index
        }

        for update in updates {
            let key = key(for: update.uid, isInput: update.isInput)
            if let index = indexByKey[key] {
                known[index] = update
            } else {
                indexByKey[key] = known.count
                known.append(update)
            }
        }

        saveKnownDevices(sortKnownDevices(known))
    }

    // MARK: - Mode Management

    public var isCustomMode: Bool {
        get { defaults.bool(forKey: customModeKey) }
        set { defaults.set(newValue, forKey: customModeKey) }
    }

    // MARK: - Priority Management

    public func sortByPriority(_ devices: [AudioDevice], type: AudioDeviceType) -> [AudioDevice] {
        let key = priorityKey(for: type)
        return sortDevices(devices, usingKey: key)
    }

    public func setPriorityUIDs(_ uids: [String], type: AudioDeviceType) {
        let key = priorityKey(for: type)
        defaults.set(uids, forKey: key)
    }

    public func getPriorityUIDs(type: AudioDeviceType) -> [String] {
        let key = priorityKey(for: type)
        return defaults.array(forKey: key) as? [String] ?? []
    }

    // MARK: - Private Helpers

    private func priorityKey(for type: AudioDeviceType) -> String {
        switch type {
        case .input:
            return inputPrioritiesKey
        case .output:
            return outputPrioritiesKey
        }
    }

    private func sortDevices(_ devices: [AudioDevice], usingKey key: String) -> [AudioDevice] {
        let priorities = defaults.array(forKey: key) as? [String] ?? []
        var priorityIndex: [String: Int] = [:]
        for (index, uid) in priorities.enumerated() where priorityIndex[uid] == nil {
            priorityIndex[uid] = index
        }

        return devices.enumerated().sorted { lhs, rhs in
            let indexA = priorityIndex[lhs.element.uid] ?? Int.max
            let indexB = priorityIndex[rhs.element.uid] ?? Int.max
            if indexA != indexB {
                return indexA < indexB
            }
            return lhs.offset < rhs.offset
        }.map { $0.element }
    }

    private func key(for uid: String, isInput: Bool) -> String {
        "\(uid)::\(isInput ? "input" : "output")"
    }

    private func dedupeKnownDevices(_ devices: [StoredDevice]) -> [StoredDevice] {
        var latestByKey: [String: StoredDevice] = [:]
        for device in devices {
            let key = key(for: device.uid, isInput: device.isInput)
            if let existing = latestByKey[key] {
                if device.lastSeen > existing.lastSeen {
                    latestByKey[key] = device
                }
            } else {
                latestByKey[key] = device
            }
        }
        return Array(latestByKey.values)
    }

    private func sortKnownDevices(_ devices: [StoredDevice]) -> [StoredDevice] {
        devices.enumerated().sorted { lhs, rhs in
            if lhs.element.lastSeen != rhs.element.lastSeen {
                return lhs.element.lastSeen > rhs.element.lastSeen
            }
            let nameCompare = lhs.element.name.localizedCaseInsensitiveCompare(rhs.element.name)
            if nameCompare != .orderedSame {
                return nameCompare == .orderedAscending
            }
            if lhs.element.uid != rhs.element.uid {
                return lhs.element.uid < rhs.element.uid
            }
            if lhs.element.isInput != rhs.element.isInput {
                return lhs.element.isInput && !rhs.element.isInput
            }
            return lhs.offset < rhs.offset
        }.map { $0.element }
    }

}
