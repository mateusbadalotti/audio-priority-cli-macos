import Foundation

public enum IdentifierResolutionError: LocalizedError {
    case invalidIndex(Int, max: Int, type: AudioDeviceType)
    case nonNumeric(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidIndex(index, max, type):
            let label = type == .output ? "output" : "input"
            if max == 0 {
                return "No \(label) devices available."
            }
            return "Invalid index \(index). Valid \(label) indexes are 1-\(max)."
        case let .nonNumeric(value):
            return "Invalid identifier \"\(value)\". Use numeric indexes."
        }
    }
}

public struct IdentifierResolver {
    public init() {}

    public func splitIdentifiers(_ args: [String]) -> [String] {
        var identifiers: [String] = []
        for arg in args {
            let parts = arg.split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            for part in parts where !part.isEmpty {
                identifiers.append(part)
            }
        }
        return identifiers
    }

    public func resolveUIDs(type: AudioDeviceType, identifiers: [String], devices: [AudioDevice]) throws -> [String] {
        var uids: [String] = []
        for identifier in identifiers {
            guard let index = Int(identifier) else {
                throw IdentifierResolutionError.nonNumeric(identifier)
            }
            let zeroBased = index - 1
            guard zeroBased >= 0, zeroBased < devices.count else {
                throw IdentifierResolutionError.invalidIndex(index, max: devices.count, type: type)
            }
            uids.append(devices[zeroBased].uid)
        }
        return uids
    }
}
