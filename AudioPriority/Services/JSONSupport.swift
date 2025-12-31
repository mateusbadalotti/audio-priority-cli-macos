import Foundation
import CoreAudio

public struct AudioPriorityJSONListPayload: Codable {
    public let known: Bool
    public let output: [AudioPriorityJSONListDevice]
    public let input: [AudioPriorityJSONListDevice]

    public init(known: Bool,
                output: [AudioPriorityJSONListDevice],
                input: [AudioPriorityJSONListDevice]) {
        self.known = known
        self.output = output
        self.input = input
    }
}

public struct AudioPriorityJSONListDevice: Codable {
    public let index: Int
    public let uid: String
    public let name: String
    public let type: String
    public let isConnected: Bool
    public let lastSeen: Date?
    public let lastSeenRelative: String?

    public init(index: Int,
                uid: String,
                name: String,
                type: String,
                isConnected: Bool,
                lastSeen: Date?,
                lastSeenRelative: String?) {
        self.index = index
        self.uid = uid
        self.name = name
        self.type = type
        self.isConnected = isConnected
        self.lastSeen = lastSeen
        self.lastSeenRelative = lastSeenRelative
    }
}

public struct AudioPriorityJSONStatusPayload: Codable {
    public let launchAgentInstalled: Bool
    public let launchAgentRunning: Bool
    public let mode: String
    public let defaultInput: AudioPriorityJSONDefaultDevice?
    public let defaultOutput: AudioPriorityJSONDefaultDevice?

    public init(launchAgentInstalled: Bool,
                launchAgentRunning: Bool,
                mode: String,
                defaultInput: AudioPriorityJSONDefaultDevice?,
                defaultOutput: AudioPriorityJSONDefaultDevice?) {
        self.launchAgentInstalled = launchAgentInstalled
        self.launchAgentRunning = launchAgentRunning
        self.mode = mode
        self.defaultInput = defaultInput
        self.defaultOutput = defaultOutput
    }
}

public struct AudioPriorityJSONDefaultDevice: Codable {
    public let id: UInt32
    public let uid: String?
    public let name: String?
    public let isConnected: Bool

    public init(id: UInt32,
                uid: String?,
                name: String?,
                isConnected: Bool) {
        self.id = id
        self.uid = uid
        self.name = name
        self.isConnected = isConnected
    }
}

public struct AudioPriorityJSONPrioritiesPayload: Codable {
    public let output: [AudioPriorityJSONPriorityDevice]
    public let input: [AudioPriorityJSONPriorityDevice]

    public init(output: [AudioPriorityJSONPriorityDevice],
                input: [AudioPriorityJSONPriorityDevice]) {
        self.output = output
        self.input = input
    }
}

public struct AudioPriorityJSONPriorityDevice: Codable {
    public let index: Int
    public let uid: String
    public let name: String?
    public let isConnected: Bool

    public init(index: Int,
                uid: String,
                name: String?,
                isConnected: Bool) {
        self.index = index
        self.uid = uid
        self.name = name
        self.isConnected = isConnected
    }
}

public enum AudioPriorityJSON {
    public static func listPayload(known: Bool,
                                   outputDevices: [AudioDevice],
                                   inputDevices: [AudioDevice]) -> AudioPriorityJSONListPayload {
        let output = outputDevices.enumerated().map { index, device in
            AudioPriorityJSONListDevice(
                index: index + 1,
                uid: device.uid,
                name: device.name,
                type: device.type.rawValue,
                isConnected: device.isConnected,
                lastSeen: nil,
                lastSeenRelative: nil
            )
        }
        let input = inputDevices.enumerated().map { index, device in
            AudioPriorityJSONListDevice(
                index: index + 1,
                uid: device.uid,
                name: device.name,
                type: device.type.rawValue,
                isConnected: device.isConnected,
                lastSeen: nil,
                lastSeenRelative: nil
            )
        }
        return AudioPriorityJSONListPayload(known: known, output: output, input: input)
    }

    public static func listPayload(knownDevices: [StoredDevice],
                                   connectedDevices: [AudioDevice]) -> AudioPriorityJSONListPayload {
        let connectedKeys = Set(connectedDevices.map { connectedKey(for: $0.uid, type: $0.type) })

        let output = knownDevices
            .filter { !$0.isInput }
            .enumerated()
            .map { index, device in
                AudioPriorityJSONListDevice(
                    index: index + 1,
                    uid: device.uid,
                    name: device.name,
                    type: AudioDeviceType.output.rawValue,
                    isConnected: connectedKeys.contains(connectedKey(for: device.uid, type: .output)),
                    lastSeen: device.lastSeen,
                    lastSeenRelative: device.lastSeenRelative
                )
            }

        let input = knownDevices
            .filter { $0.isInput }
            .enumerated()
            .map { index, device in
                AudioPriorityJSONListDevice(
                    index: index + 1,
                    uid: device.uid,
                    name: device.name,
                    type: AudioDeviceType.input.rawValue,
                    isConnected: connectedKeys.contains(connectedKey(for: device.uid, type: .input)),
                    lastSeen: device.lastSeen,
                    lastSeenRelative: device.lastSeenRelative
                )
            }

        return AudioPriorityJSONListPayload(known: true, output: output, input: input)
    }

    public static func prioritiesPayload(priorityOutput: [String],
                                         priorityInput: [String],
                                         knownDevices: [StoredDevice],
                                         connectedDevices: [AudioDevice]) -> AudioPriorityJSONPrioritiesPayload {
        let connectedKeys = Set(connectedDevices.map { connectedKey(for: $0.uid, type: $0.type) })
        let knownByKey = Dictionary(uniqueKeysWithValues: knownDevices.map {
            (knownKey(for: $0.uid, isInput: $0.isInput), $0)
        })

        let output = priorityOutput.enumerated().map { index, uid in
            let known = knownByKey[knownKey(for: uid, isInput: false)]
            let isConnected = connectedKeys.contains(connectedKey(for: uid, type: .output))
            return AudioPriorityJSONPriorityDevice(
                index: index + 1,
                uid: uid,
                name: known?.name,
                isConnected: isConnected
            )
        }

        let input = priorityInput.enumerated().map { index, uid in
            let known = knownByKey[knownKey(for: uid, isInput: true)]
            let isConnected = connectedKeys.contains(connectedKey(for: uid, type: .input))
            return AudioPriorityJSONPriorityDevice(
                index: index + 1,
                uid: uid,
                name: known?.name,
                isConnected: isConnected
            )
        }

        return AudioPriorityJSONPrioritiesPayload(output: output, input: input)
    }

    public static func defaultDevice(id: AudioObjectID?,
                                     devices: [AudioDevice]) -> AudioPriorityJSONDefaultDevice? {
        guard let id else { return nil }
        let match = devices.first { $0.id == id }
        return AudioPriorityJSONDefaultDevice(
            id: id,
            uid: match?.uid,
            name: match?.name,
            isConnected: match != nil
        )
    }

    private static func connectedKey(for uid: String, type: AudioDeviceType) -> String {
        "\(uid)::\(type.rawValue)"
    }

    private static func knownKey(for uid: String, isInput: Bool) -> String {
        "\(uid)::\(isInput ? "input" : "output")"
    }
}
