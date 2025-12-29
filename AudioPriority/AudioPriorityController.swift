import Foundation
import CoreAudio

final class AudioPriorityController {
    private let deviceService = AudioDeviceService()
    let priorityManager = PriorityManager()

    private(set) var inputDevices: [AudioDevice] = []
    private(set) var outputDevices: [AudioDevice] = []
    private(set) var currentInputId: AudioObjectID?
    private(set) var currentOutputId: AudioObjectID?

    var isCustomMode: Bool {
        get { priorityManager.isCustomMode }
        set { priorityManager.isCustomMode = newValue }
    }

    init() {
        refreshDevices()
    }

    func startListening() {
        deviceService.onDevicesChanged = { [weak self] in
            self?.handleDeviceChange()
        }
        deviceService.startListening()
    }

    func stopListening() {
        deviceService.stopListening()
    }

    func refreshDevices() {
        let connectedDevices = deviceService.getDevices()

        for device in connectedDevices {
            priorityManager.rememberDevice(device.uid, name: device.name, isInput: device.type == .input)
        }

        let connectedInputs = connectedDevices.filter { $0.type == .input }
        let connectedOutputs = connectedDevices.filter { $0.type == .output }

        inputDevices = priorityManager.sortByPriority(connectedInputs, type: .input)
        outputDevices = priorityManager.sortByPriority(connectedOutputs, type: .output)

        currentInputId = deviceService.getCurrentDefaultDevice(type: .input)
        currentOutputId = deviceService.getCurrentDefaultDevice(type: .output)
    }

    func setCustomMode(_ enabled: Bool) {
        isCustomMode = enabled
        if !enabled {
            applyHighestPriorityDevices()
        }
    }

    func applyHighestPriorityDevices() {
        applyHighestPriorityInput()
        applyHighestPriorityOutput()
    }

    func applyHighestPriorityInput() {
        refreshDevices()
        if let first = inputDevices.first(where: { $0.isConnected }) {
            deviceService.setDefaultDevice(first.id, type: .input)
            currentInputId = first.id
        }
    }

    func applyHighestPriorityOutput() {
        refreshDevices()
        if let first = outputDevices.first(where: { $0.isConnected }) {
            deviceService.setDefaultDevice(first.id, type: .output)
            currentOutputId = first.id
        }
    }

    func forgetDevice(uid: String) {
        priorityManager.forgetDevice(uid)
    }

    func setPriorities(type: AudioDeviceType, orderedUIDs: [String]) {
        refreshDevices()
        let knownUIDs = priorityManager.getKnownDevices()
            .filter { $0.isInput == (type == .input) }
            .map { $0.uid }

        let fallbackUIDs = (type == .input ? inputDevices : outputDevices).map { $0.uid }
        let baseUIDs = knownUIDs.isEmpty ? fallbackUIDs : knownUIDs

        var newOrder: [String] = []
        for uid in orderedUIDs where !newOrder.contains(uid) {
            newOrder.append(uid)
        }
        for uid in baseUIDs where !newOrder.contains(uid) {
            newOrder.append(uid)
        }

        priorityManager.setPriorityUIDs(newOrder, type: type)
        if !isCustomMode {
            applyHighestPriorityDevices()
        }
    }

    private func handleDeviceChange() {
        refreshDevices()
        if !isCustomMode {
            applyHighestPriorityDevices()
        }
    }
}
