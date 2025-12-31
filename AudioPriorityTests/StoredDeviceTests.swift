import XCTest
@testable import AudioPriorityCore

final class StoredDeviceTests: XCTestCase {
    func testLastSeenRelativeNow() {
        let device = StoredDevice(uid: "uid", name: "Device", isInput: true, lastSeen: Date().addingTimeInterval(-30))
        XCTAssertEqual(device.lastSeenRelative, "now")
    }

    func testLastSeenRelativeMinutes() {
        let device = StoredDevice(uid: "uid", name: "Device", isInput: true, lastSeen: Date().addingTimeInterval(-5 * 60))
        XCTAssertEqual(device.lastSeenRelative, "5m ago")
    }

    func testLastSeenRelativeHours() {
        let device = StoredDevice(uid: "uid", name: "Device", isInput: true, lastSeen: Date().addingTimeInterval(-2 * 3600))
        XCTAssertEqual(device.lastSeenRelative, "2h ago")
    }
}
