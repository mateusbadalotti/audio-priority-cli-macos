import XCTest
@testable import AudioPriorityCore

final class JSONSupportTests: XCTestCase {
    func testListPayloadForConnectedDevicesUsesIndexesAndConnectionState() {
        let outputDevices = [
            AudioDevice(id: 1, uid: "out-1", name: "Speakers", type: .output),
            AudioDevice(id: 2, uid: "out-2", name: "HDMI", type: .output, isConnected: false)
        ]
        let inputDevices = [
            AudioDevice(id: 3, uid: "in-1", name: "Mic", type: .input, isConnected: false)
        ]

        let payload = AudioPriorityJSON.listPayload(known: false, outputDevices: outputDevices, inputDevices: inputDevices)

        XCTAssertFalse(payload.known)
        XCTAssertEqual(payload.output.map(\.index), [1, 2])
        XCTAssertEqual(payload.output.map(\.uid), ["out-1", "out-2"])
        XCTAssertEqual(payload.output.map(\.isConnected), [true, false])
        XCTAssertNil(payload.output[0].lastSeen)
        XCTAssertNil(payload.output[0].lastSeenRelative)
        XCTAssertEqual(payload.input.map(\.index), [1])
        XCTAssertEqual(payload.input.map(\.uid), ["in-1"])
        XCTAssertEqual(payload.input.map(\.isConnected), [false])
    }

    func testListPayloadForKnownDevicesIncludesLastSeenAndConnectionState() {
        let now = Date()
        let knownDevices = [
            StoredDevice(uid: "out-1", name: "Speakers", isInput: false, lastSeen: now),
            StoredDevice(uid: "in-1", name: "Mic", isInput: true, lastSeen: now.addingTimeInterval(-3600)),
            StoredDevice(uid: "out-2", name: "HDMI", isInput: false, lastSeen: now.addingTimeInterval(-7200))
        ]
        let connectedDevices = [
            AudioDevice(id: 1, uid: "out-1", name: "Speakers", type: .output),
            AudioDevice(id: 2, uid: "in-1", name: "Mic", type: .input)
        ]

        let payload = AudioPriorityJSON.listPayload(knownDevices: knownDevices, connectedDevices: connectedDevices)

        XCTAssertTrue(payload.known)
        XCTAssertEqual(payload.output.map(\.uid), ["out-1", "out-2"])
        XCTAssertEqual(payload.output.map(\.isConnected), [true, false])
        XCTAssertNotNil(payload.output[0].lastSeen)
        XCTAssertNotNil(payload.output[0].lastSeenRelative)
        XCTAssertEqual(payload.input.map(\.uid), ["in-1"])
        XCTAssertEqual(payload.input.map(\.isConnected), [true])
    }

    func testPrioritiesPayloadIncludesNamesAndConnectionState() {
        let now = Date()
        let knownDevices = [
            StoredDevice(uid: "out-1", name: "Speakers", isInput: false, lastSeen: now),
            StoredDevice(uid: "in-1", name: "Mic", isInput: true, lastSeen: now)
        ]
        let connectedDevices = [
            AudioDevice(id: 1, uid: "out-1", name: "Speakers", type: .output),
            AudioDevice(id: 2, uid: "in-1", name: "Mic", type: .input)
        ]

        let payload = AudioPriorityJSON.prioritiesPayload(
            priorityOutput: ["out-1", "out-2"],
            priorityInput: ["in-1"],
            knownDevices: knownDevices,
            connectedDevices: connectedDevices
        )

        XCTAssertEqual(payload.output.map(\.uid), ["out-1", "out-2"])
        XCTAssertEqual(payload.output[0].name, "Speakers")
        XCTAssertEqual(payload.output[0].isConnected, true)
        XCTAssertNil(payload.output[1].name)
        XCTAssertEqual(payload.output[1].isConnected, false)
        XCTAssertEqual(payload.input.map(\.uid), ["in-1"])
        XCTAssertEqual(payload.input[0].name, "Mic")
        XCTAssertEqual(payload.input[0].isConnected, true)
    }

    func testDefaultDeviceIncludesMatchedDetailsWhenPresent() {
        let devices = [
            AudioDevice(id: 42, uid: "out-1", name: "Speakers", type: .output)
        ]

        let matched = AudioPriorityJSON.defaultDevice(id: 42, devices: devices)
        XCTAssertEqual(matched?.id, 42)
        XCTAssertEqual(matched?.uid, "out-1")
        XCTAssertEqual(matched?.name, "Speakers")
        XCTAssertEqual(matched?.isConnected, true)

        let missing = AudioPriorityJSON.defaultDevice(id: 99, devices: devices)
        XCTAssertEqual(missing?.id, 99)
        XCTAssertNil(missing?.uid)
        XCTAssertNil(missing?.name)
        XCTAssertEqual(missing?.isConnected, false)

        let none = AudioPriorityJSON.defaultDevice(id: nil, devices: devices)
        XCTAssertNil(none)
    }
}
