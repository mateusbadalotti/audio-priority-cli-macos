import Foundation
import CoreAudio

open class AudioDeviceService {
    var onDevicesChanged: (() -> Void)?
    var onDefaultDevicesChanged: (() -> Void)?

    private var devicesListenerBlock: AudioObjectPropertyListenerBlock?
    private var defaultsListenerBlock: AudioObjectPropertyListenerBlock?
    private let listenerQueue = DispatchQueue(label: "AudioPriority.AudioDeviceService")
    private let cacheLock = NSLock()
    private var deviceInfoCache: [AudioObjectID: DeviceInfo] = [:]

    public init() {}

    open func getDevices() -> [AudioDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr, dataSize > 0 else { return [] }

        var deviceCount = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIds = [AudioObjectID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIds
        )

        guard status == noErr else { return [] }

        let actualCount = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        if actualCount > deviceIds.count {
            deviceCount = actualCount
            deviceIds = [AudioObjectID](repeating: 0, count: deviceCount)
            var retrySize = UInt32(deviceCount * MemoryLayout<AudioObjectID>.size)
            status = AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &propertyAddress,
                0,
                nil,
                &retrySize,
                &deviceIds
            )
            guard status == noErr else { return [] }
            dataSize = retrySize
        }

        var devices: [AudioDevice] = []
        var infoCache = snapshotDeviceInfoCache()

        let finalCount = min(Int(dataSize) / MemoryLayout<AudioObjectID>.size, deviceIds.count)
        for deviceId in deviceIds.prefix(finalCount) {
            let hasInput = hasStreams(deviceId: deviceId, scope: kAudioDevicePropertyScopeInput)
            let hasOutput = hasStreams(deviceId: deviceId, scope: kAudioDevicePropertyScopeOutput)
            guard hasInput || hasOutput else { continue }

            let info: DeviceInfo
            if let cached = infoCache[deviceId] {
                info = cached
            } else {
                guard let fetched = fetchDeviceInfo(id: deviceId) else { continue }
                infoCache[deviceId] = fetched
                info = fetched
            }

            if hasInput {
                devices.append(AudioDevice(id: deviceId, uid: info.uid, name: info.name, type: .input))
            }
            if hasOutput {
                devices.append(AudioDevice(id: deviceId, uid: info.uid, name: info.name, type: .output))
            }
        }

        storeDeviceInfoCache(infoCache)
        return devices
    }

    open func getCurrentDefaultDevice(type: AudioDeviceType) -> AudioObjectID? {
        let selector: AudioObjectPropertySelector = type == .input
            ? kAudioHardwarePropertyDefaultInputDevice
            : kAudioHardwarePropertyDefaultOutputDevice

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceId: AudioObjectID = 0
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceId
        )

        return status == noErr ? deviceId : nil
    }

    @discardableResult
    open func setDefaultDevice(_ deviceId: AudioObjectID, type: AudioDeviceType) -> Bool {
        let selector: AudioObjectPropertySelector = type == .input
            ? kAudioHardwarePropertyDefaultInputDevice
            : kAudioHardwarePropertyDefaultOutputDevice

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var mutableDeviceId = deviceId
        let dataSize = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            dataSize,
            &mutableDeviceId
        )
        if status != noErr {
            logError("Failed to set default \(type.rawValue) device (status: \(status))")
            return false
        }
        return true
    }

    open func startListening() {
        guard devicesListenerBlock == nil, defaultsListenerBlock == nil else { return }
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        devicesListenerBlock = { [weak self] _, _ in
            self?.invalidateDeviceInfoCache()
            self?.onDevicesChanged?()
        }

        defaultsListenerBlock = { [weak self] _, _ in
            self?.onDefaultDevicesChanged?()
        }

        var allSucceeded = true

        let deviceStatus = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            listenerQueue,
            devicesListenerBlock!
        )
        if deviceStatus != noErr {
            logError("Failed to add device listener (status: \(deviceStatus))")
            allSucceeded = false
        }

        // Also listen to default device changes
        var inputDefaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let inputStatus = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &inputDefaultAddress,
            listenerQueue,
            defaultsListenerBlock!
        )
        if inputStatus != noErr {
            logError("Failed to add default input listener (status: \(inputStatus))")
            allSucceeded = false
        }

        var outputDefaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let outputStatus = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &outputDefaultAddress,
            listenerQueue,
            defaultsListenerBlock!
        )
        if outputStatus != noErr {
            logError("Failed to add default output listener (status: \(outputStatus))")
            allSucceeded = false
        }

        if !allSucceeded {
            stopListening()
        }
    }

    open func stopListening() {
        if let block = devicesListenerBlock {
            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            let deviceStatus = AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &propertyAddress,
                listenerQueue,
                block
            )
            if deviceStatus != noErr {
                logError("Failed to remove device listener (status: \(deviceStatus))")
            }
        }

        // Also remove default device change listeners
        if let block = defaultsListenerBlock {
            var inputDefaultAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let inputStatus = AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &inputDefaultAddress,
                listenerQueue,
                block
            )
            if inputStatus != noErr {
                logError("Failed to remove default input listener (status: \(inputStatus))")
            }

            var outputDefaultAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let outputStatus = AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &outputDefaultAddress,
                listenerQueue,
                block
            )
            if outputStatus != noErr {
                logError("Failed to remove default output listener (status: \(outputStatus))")
            }
        }

        devicesListenerBlock = nil
        defaultsListenerBlock = nil
    }

    private struct DeviceInfo {
        let name: String
        let uid: String
    }

    private func fetchDeviceInfo(id: AudioObjectID) -> DeviceInfo? {
        guard let uid = getDeviceUID(id: id) else { return nil }
        let name = getDeviceName(id: id) ?? uid
        return DeviceInfo(name: name, uid: uid)
    }

    private func hasStreams(deviceId: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceId,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        return status == noErr && dataSize > 0
    }

    private func getDeviceName(id: AudioObjectID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)

        let status = withUnsafeMutableBytes(of: &name) { buffer -> OSStatus in
            guard let baseAddress = buffer.baseAddress else {
                return kAudioHardwareUnspecifiedError
            }
            return AudioObjectGetPropertyData(
                id,
                &propertyAddress,
                0,
                nil,
                &dataSize,
                baseAddress
            )
        }

        guard status == noErr, let name else { return nil }
        let string = name as String
        return string.isEmpty ? nil : string
    }

    private func getDeviceUID(id: AudioObjectID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var uid: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)

        let status = withUnsafeMutableBytes(of: &uid) { buffer -> OSStatus in
            guard let baseAddress = buffer.baseAddress else {
                return kAudioHardwareUnspecifiedError
            }
            return AudioObjectGetPropertyData(
                id,
                &propertyAddress,
                0,
                nil,
                &dataSize,
                baseAddress
            )
        }

        guard status == noErr, let uid else { return nil }
        let string = uid as String
        return string.isEmpty ? nil : string
    }

    private func logError(_ message: String) {
        guard let data = (message + "\n").data(using: .utf8) else { return }
        FileHandle.standardError.write(data)
    }

    private func snapshotDeviceInfoCache() -> [AudioObjectID: DeviceInfo] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return deviceInfoCache
    }

    private func storeDeviceInfoCache(_ cache: [AudioObjectID: DeviceInfo]) {
        cacheLock.lock()
        deviceInfoCache = cache
        cacheLock.unlock()
    }

    private func invalidateDeviceInfoCache() {
        cacheLock.lock()
        deviceInfoCache.removeAll()
        cacheLock.unlock()
    }

    deinit {
        stopListening()
    }
}
