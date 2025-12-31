import Foundation
import CoreAudio

public final class AudioPriorityController: @unchecked Sendable {
    private let deviceService: AudioDeviceService
    public let priorityManager: PriorityManager

    public private(set) var inputDevices: [AudioDevice] {
        get { performSync { _inputDevices } }
        set { performSync { _inputDevices = newValue } }
    }
    public private(set) var outputDevices: [AudioDevice] {
        get { performSync { _outputDevices } }
        set { performSync { _outputDevices = newValue } }
    }
    public private(set) var currentInputId: AudioObjectID? {
        get { performSync { _currentInputId } }
        set { performSync { _currentInputId = newValue } }
    }
    public private(set) var currentOutputId: AudioObjectID? {
        get { performSync { _currentOutputId } }
        set { performSync { _currentOutputId = newValue } }
    }
    private var _inputDevices: [AudioDevice] = []
    private var _outputDevices: [AudioDevice] = []
    private var _currentInputId: AudioObjectID?
    private var _currentOutputId: AudioObjectID?
    private var deviceChangeWorkItem: DispatchWorkItem?
    private var defaultChangeWorkItem: DispatchWorkItem?
    private var lastAppliedInput: (id: AudioObjectID, time: Date)?
    private var lastAppliedOutput: (id: AudioObjectID, time: Date)?
    private var connectedDeviceKeys: Set<String> = []
    private let deviceChangeDebounce: TimeInterval
    private let defaultChangeDebounce: TimeInterval
    private let selfChangeWindow: TimeInterval
    private let eventQueue = DispatchQueue(label: "AudioPriority.Controller")
    private let eventQueueKey = DispatchSpecificKey<Void>()

    public var isCustomMode: Bool {
        get { priorityManager.isCustomMode }
        set { priorityManager.isCustomMode = newValue }
    }

    public init(deviceService: AudioDeviceService = AudioDeviceService(),
                priorityManager: PriorityManager = PriorityManager(),
                deviceChangeDebounce: TimeInterval = 0.2,
                defaultChangeDebounce: TimeInterval = 0.2,
                selfChangeWindow: TimeInterval = 0.5) {
        self.deviceService = deviceService
        self.priorityManager = priorityManager
        self.deviceChangeDebounce = deviceChangeDebounce
        self.defaultChangeDebounce = defaultChangeDebounce
        self.selfChangeWindow = selfChangeWindow
        eventQueue.setSpecific(key: eventQueueKey, value: ())
        refreshDevices(updateKnownDevices: true)
    }

    public func startListening() {
        deviceService.onDevicesChanged = { [weak self] in
            self?.handleDeviceChange()
        }
        deviceService.onDefaultDevicesChanged = { [weak self] in
            self?.handleDefaultChange()
        }
        deviceService.startListening()
    }

    public func stopListening() {
        deviceService.stopListening()
        eventQueue.async { [weak self] in
            self?.deviceChangeWorkItem?.cancel()
            self?.deviceChangeWorkItem = nil
            self?.defaultChangeWorkItem?.cancel()
            self?.defaultChangeWorkItem = nil
        }
    }

    public func refreshDevices(updateKnownDevices: Bool = false) {
        performSync {
            let connectedDevices = deviceService.getDevices()

            if updateKnownDevices {
                let currentKeys = Set(connectedDevices.map { deviceKey(for: $0) })
                let newlyConnectedKeys = currentKeys.subtracting(connectedDeviceKeys)
                if !newlyConnectedKeys.isEmpty {
                    let newlyConnectedDevices = connectedDevices.filter { device in
                        newlyConnectedKeys.contains(deviceKey(for: device))
                    }
                    priorityManager.rememberDevices(newlyConnectedDevices)
                }
                connectedDeviceKeys = currentKeys
            }

            let connectedInputs = connectedDevices.filter { $0.type == .input }
            let connectedOutputs = connectedDevices.filter { $0.type == .output }

            _inputDevices = priorityManager.sortByPriority(connectedInputs, type: .input)
            _outputDevices = priorityManager.sortByPriority(connectedOutputs, type: .output)

            _currentInputId = deviceService.getCurrentDefaultDevice(type: .input)
            _currentOutputId = deviceService.getCurrentDefaultDevice(type: .output)
        }
    }

    public func setCustomMode(_ enabled: Bool) {
        performSync {
            isCustomMode = enabled
            if !enabled {
                applyHighestPriorityDevices(refresh: false)
            }
        }
    }

    public func applyHighestPriorityDevices(refresh: Bool = true) {
        performSync {
            if refresh {
                refreshDevices()
            }
            applyHighestPriorityInput(using: _inputDevices, currentId: _currentInputId)
            applyHighestPriorityOutput(using: _outputDevices, currentId: _currentOutputId)
        }
    }

    public func applyHighestPriorityInput() {
        performSync {
            refreshDevices()
            applyHighestPriorityInput(using: _inputDevices, currentId: _currentInputId)
        }
    }

    public func applyHighestPriorityOutput() {
        performSync {
            refreshDevices()
            applyHighestPriorityOutput(using: _outputDevices, currentId: _currentOutputId)
        }
    }

    public func forgetDevice(uid: String) {
        performSync {
            priorityManager.forgetDevice(uid)
        }
    }

    public func forgetDevice(uid: String, type: AudioDeviceType) {
        performSync {
            priorityManager.forgetDevice(uid, isInput: type == .input)
        }
    }

    public func setPriorities(type: AudioDeviceType, orderedUIDs: [String], refresh: Bool = true) {
        performSync {
            if refresh {
                refreshDevices()
            }
            let knownUIDs = priorityManager.getKnownDevices()
                .filter { $0.isInput == (type == .input) }
                .map { $0.uid }

            let fallbackUIDs = (type == .input ? _inputDevices : _outputDevices).map { $0.uid }
            let baseUIDs = knownUIDs.isEmpty ? fallbackUIDs : knownUIDs

            var newOrder: [String] = []
            var seen = Set<String>()
            for uid in orderedUIDs where seen.insert(uid).inserted {
                newOrder.append(uid)
            }
            for uid in baseUIDs where seen.insert(uid).inserted {
                newOrder.append(uid)
            }

            priorityManager.setPriorityUIDs(newOrder, type: type)
            if type == .input {
                _inputDevices = priorityManager.sortByPriority(_inputDevices, type: .input)
            } else {
                _outputDevices = priorityManager.sortByPriority(_outputDevices, type: .output)
            }
            if !isCustomMode {
                applyHighestPriorityDevices(refresh: false)
            }
        }
    }

    private func handleDeviceChange() {
        eventQueue.async { [weak self] in
            guard let self else { return }
            self.deviceChangeWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.refreshDevices(updateKnownDevices: true)
                if !self.isCustomMode {
                    self.applyHighestPriorityDevices(refresh: false)
                }
            }
            self.deviceChangeWorkItem = workItem
            self.eventQueue.asyncAfter(deadline: .now() + deviceChangeDebounce, execute: workItem)
        }
    }

    private func handleDefaultChange() {
        eventQueue.async { [weak self] in
            guard let self else { return }
            self.defaultChangeWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if self.shouldSuppressDefaultChange() {
                    return
                }
                self.refreshDevices()
                if !self.isCustomMode {
                    self.applyHighestPriorityDevices(refresh: false)
                }
            }
            self.defaultChangeWorkItem = workItem
            self.eventQueue.asyncAfter(deadline: .now() + defaultChangeDebounce, execute: workItem)
        }
    }

    private func shouldSuppressDefaultChange() -> Bool {
        let now = Date()
        let actualInput = deviceService.getCurrentDefaultDevice(type: .input)
        let actualOutput = deviceService.getCurrentDefaultDevice(type: .output)

        let inputChanged = actualInput != currentInputId
        let outputChanged = actualOutput != currentOutputId

        if !inputChanged && !outputChanged {
            return false
        }

        if inputChanged {
            guard let last = lastAppliedInput,
                  now.timeIntervalSince(last.time) <= selfChangeWindow,
                  actualInput == last.id else {
                return false
            }
        }

        if outputChanged {
            guard let last = lastAppliedOutput,
                  now.timeIntervalSince(last.time) <= selfChangeWindow,
                  actualOutput == last.id else {
                return false
            }
        }

        if inputChanged || outputChanged {
            currentInputId = actualInput
            currentOutputId = actualOutput
            return true
        }

        return true
    }

    private func applyHighestPriorityInput(using devices: [AudioDevice], currentId: AudioObjectID?) {
        if let first = devices.first(where: { $0.isConnected }), first.id != currentId {
            if deviceService.setDefaultDevice(first.id, type: .input) {
                _currentInputId = first.id
                lastAppliedInput = (first.id, Date())
            }
        }
    }

    private func applyHighestPriorityOutput(using devices: [AudioDevice], currentId: AudioObjectID?) {
        if let first = devices.first(where: { $0.isConnected }), first.id != currentId {
            if deviceService.setDefaultDevice(first.id, type: .output) {
                _currentOutputId = first.id
                lastAppliedOutput = (first.id, Date())
            }
        }
    }

    private func deviceKey(for device: AudioDevice) -> String {
        "\(device.uid)::\(device.type.rawValue)"
    }

    private func performSync<T>(_ work: () -> T) -> T {
        if DispatchQueue.getSpecific(key: eventQueueKey) != nil {
            return work()
        }
        return eventQueue.sync { work() }
    }
}
