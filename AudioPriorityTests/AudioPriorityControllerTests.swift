import CoreAudio
import XCTest
@testable import AudioPriorityCore

final class AudioPriorityControllerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private let debounceInterval: TimeInterval = 0.05

    override func setUp() {
        super.setUp()
        suiteName = "AudioPriorityTests.Controller.\(UUID().uuidString)"
        guard let suiteDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create test UserDefaults suite")
            defaults = UserDefaults.standard
            return
        }
        defaults = suiteDefaults
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSetPrioritiesAppliesNewOrderWithoutExtraRefresh() {
        let fakeService = FakeAudioDeviceService()
        fakeService.devices = [
            AudioDevice(id: 1, uid: "uid-1", name: "A", type: .output),
            AudioDevice(id: 2, uid: "uid-2", name: "B", type: .output),
        ]
        fakeService.currentOutput = 1

        let manager = PriorityManager(defaults: defaults)
        let controller = makeController(service: fakeService, manager: manager)

        controller.setPriorities(type: .output, orderedUIDs: ["uid-2"])

        XCTAssertEqual(fakeService.currentOutput, 2)
        XCTAssertEqual(fakeService.setCalls.last?.1, .output)
    }

    func testDefaultChangeSuppressionSkipsRedundantApply() {
        let fakeService = FakeAudioDeviceService()
        fakeService.devices = [
            AudioDevice(id: 1, uid: "uid-1", name: "A", type: .output),
            AudioDevice(id: 2, uid: "uid-2", name: "B", type: .output),
        ]
        fakeService.currentOutput = 1

        let manager = PriorityManager(defaults: defaults)
        manager.setPriorityUIDs(["uid-2", "uid-1"], type: .output)
        let controller = makeController(service: fakeService, manager: manager)
        controller.startListening()

        controller.applyHighestPriorityOutput()
        let initialSetCalls = fakeService.setCalls.count

        fakeService.triggerDefaultChange()

        waitForDebounce()

        XCTAssertEqual(fakeService.setCalls.count, initialSetCalls)
    }

    func testDefaultChangeDoesNotUpdateLastSeen() {
        let fakeService = FakeAudioDeviceService()
        fakeService.devices = [
            AudioDevice(id: 1, uid: "uid-1", name: "A", type: .output),
            AudioDevice(id: 2, uid: "uid-2", name: "B", type: .output),
        ]
        fakeService.currentOutput = 1

        let manager = PriorityManager(defaults: defaults)
        let controller = makeController(service: fakeService, manager: manager)
        controller.startListening()

        let initialKnown = manager.getKnownDevices()
        let initialMap = Dictionary(uniqueKeysWithValues: initialKnown.map { device in
            ("\(device.uid)::\(device.isInput)", device.lastSeen)
        })

        fakeService.currentOutput = 2
        fakeService.triggerDefaultChange()

        waitForDebounce()

        let updatedMap = Dictionary(uniqueKeysWithValues: manager.getKnownDevices().map { device in
            ("\(device.uid)::\(device.isInput)", device.lastSeen)
        })

        for (key, timestamp) in initialMap {
            XCTAssertEqual(updatedMap[key], timestamp, "Last seen should not change for \(key)")
        }
    }

    func testDeviceChangeAddsNewDeviceAndKeepsExistingLastSeen() {
        let fakeService = FakeAudioDeviceService()
        fakeService.devices = [
            AudioDevice(id: 1, uid: "uid-1", name: "A", type: .output),
        ]

        let manager = PriorityManager(defaults: defaults)
        let controller = makeController(service: fakeService, manager: manager)
        controller.startListening()

        let initialKnown = manager.getKnownDevices()
        XCTAssertEqual(initialKnown.count, 1)
        let initialTimestamp = initialKnown.first?.lastSeen

        fakeService.devices.append(AudioDevice(id: 2, uid: "uid-2", name: "B", type: .output))
        fakeService.triggerDeviceChange()

        waitForDebounce()

        let updatedKnown = manager.getKnownDevices()
        XCTAssertEqual(updatedKnown.count, 2)
        let existing = updatedKnown.first { $0.uid == "uid-1" && !$0.isInput }
        XCTAssertEqual(existing?.lastSeen, initialTimestamp)
        XCTAssertNotNil(updatedKnown.first { $0.uid == "uid-2" && !$0.isInput })
    }

    private func makeController(service: AudioDeviceService, manager: PriorityManager) -> AudioPriorityController {
        AudioPriorityController(
            deviceService: service,
            priorityManager: manager,
            deviceChangeDebounce: debounceInterval,
            defaultChangeDebounce: debounceInterval
        )
    }

    private func waitForDebounce() {
        let expectation = expectation(description: "debounce")
        DispatchQueue.global().asyncAfter(deadline: .now() + debounceInterval * 4) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }
}

private final class FakeAudioDeviceService: AudioDeviceService {
    var devices: [AudioDevice] = []
    var currentInput: AudioObjectID?
    var currentOutput: AudioObjectID?
    var setCalls: [(AudioObjectID, AudioDeviceType)] = []

    override func getDevices() -> [AudioDevice] {
        devices
    }

    override func getCurrentDefaultDevice(type: AudioDeviceType) -> AudioObjectID? {
        type == .input ? currentInput : currentOutput
    }

    override func setDefaultDevice(_ deviceId: AudioObjectID, type: AudioDeviceType) -> Bool {
        setCalls.append((deviceId, type))
        if type == .input {
            currentInput = deviceId
        } else {
            currentOutput = deviceId
        }
        return true
    }

    override func startListening() {}

    override func stopListening() {}

    func triggerDeviceChange() {
        onDevicesChanged?()
    }

    func triggerDefaultChange() {
        onDefaultDevicesChanged?()
    }
}
