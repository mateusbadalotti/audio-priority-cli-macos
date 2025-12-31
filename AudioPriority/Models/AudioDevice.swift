import Foundation
import CoreAudio

public enum AudioDeviceType: String, Codable, Sendable {
    case input
    case output
}

public struct AudioDevice: Identifiable, Equatable, Hashable {
    public let id: AudioObjectID
    public let uid: String
    public let name: String
    public let type: AudioDeviceType
    public var isConnected: Bool = true

    public init(id: AudioObjectID, uid: String, name: String, type: AudioDeviceType, isConnected: Bool = true) {
        self.id = id
        self.uid = uid
        self.name = name
        self.type = type
        self.isConnected = isConnected
    }
}
