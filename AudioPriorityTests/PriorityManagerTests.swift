import XCTest
@testable import AudioPriorityCore

final class PriorityManagerTests: XCTestCase {
    private var manager: PriorityManager!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AudioPriorityTests.\(UUID().uuidString)"
        guard let suiteDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create test UserDefaults suite")
            defaults = UserDefaults.standard
            manager = PriorityManager(defaults: defaults)
            return
        }
        defaults = suiteDefaults
        manager = PriorityManager(defaults: suiteDefaults)
        resetDefaults()
    }

    override func tearDown() {
        resetDefaults()
        manager = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func resetDefaults() {
        guard let suiteName else { return }
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testSetPriorityUIDsStoresAndReads() {
        let inputUIDs = ["in-1", "in-2"]
        let outputUIDs = ["out-1", "out-2"]

        manager.setPriorityUIDs(inputUIDs, type: .input)
        manager.setPriorityUIDs(outputUIDs, type: .output)

        XCTAssertEqual(manager.getPriorityUIDs(type: .input), inputUIDs)
        XCTAssertEqual(manager.getPriorityUIDs(type: .output), outputUIDs)
    }

    func testSortByPriorityOrdersPrioritizedFirst() {
        let devices = [
            AudioDevice(id: 1, uid: "uid-1", name: "A", type: .output),
            AudioDevice(id: 2, uid: "uid-2", name: "B", type: .output),
            AudioDevice(id: 3, uid: "uid-3", name: "C", type: .output),
        ]

        manager.setPriorityUIDs(["uid-2", "uid-1"], type: .output)

        let sorted = manager.sortByPriority(devices, type: .output)

        XCTAssertEqual(sorted.map { $0.uid }, ["uid-2", "uid-1", "uid-3"])
    }

    func testSortByPriorityIgnoresDuplicatePriorityUIDs() {
        let devices = [
            AudioDevice(id: 1, uid: "uid-1", name: "A", type: .output),
            AudioDevice(id: 2, uid: "uid-2", name: "B", type: .output),
        ]

        manager.setPriorityUIDs(["uid-2", "uid-2", "uid-1"], type: .output)

        let sorted = manager.sortByPriority(devices, type: .output)

        XCTAssertEqual(sorted.map { $0.uid }, ["uid-2", "uid-1"])
    }

    func testSortByPriorityKeepsRelativeOrderForUnprioritized() {
        let devices = [
            AudioDevice(id: 1, uid: "uid-1", name: "A", type: .output),
            AudioDevice(id: 2, uid: "uid-2", name: "B", type: .output),
            AudioDevice(id: 3, uid: "uid-3", name: "C", type: .output),
            AudioDevice(id: 4, uid: "uid-4", name: "D", type: .output),
        ]

        manager.setPriorityUIDs(["uid-3"], type: .output)

        let sorted = manager.sortByPriority(devices, type: .output)

        XCTAssertEqual(sorted.map { $0.uid }, ["uid-3", "uid-1", "uid-2", "uid-4"])
    }

    func testRememberDeviceUpdatesNameAndLastSeen() {
        manager.rememberDevice("uid-x", name: "First", isInput: true)
        manager.rememberDevice("uid-x", name: "Second", isInput: true)

        let known = manager.getKnownDevices()
        XCTAssertEqual(known.count, 1)
        XCTAssertEqual(known.first?.name, "Second")
        XCTAssertNotNil(known.first?.lastSeen)
    }

    func testRememberDeviceStoresInputAndOutputSeparately() {
        manager.rememberDevice("uid-x", name: "Device In", isInput: true)
        manager.rememberDevice("uid-x", name: "Device Out", isInput: false)

        let known = manager.getKnownDevices()
        XCTAssertEqual(known.count, 2)
        XCTAssertTrue(known.contains { $0.uid == "uid-x" && $0.isInput })
        XCTAssertTrue(known.contains { $0.uid == "uid-x" && !$0.isInput })
    }

    func testForgetDeviceByTypeRemovesOnlyMatchingType() {
        manager.rememberDevice("uid-x", name: "Device In", isInput: true)
        manager.rememberDevice("uid-x", name: "Device Out", isInput: false)

        manager.forgetDevice("uid-x", isInput: true)

        let known = manager.getKnownDevices()
        XCTAssertEqual(known.count, 1)
        XCTAssertFalse(known.contains { $0.uid == "uid-x" && $0.isInput })
        XCTAssertTrue(known.contains { $0.uid == "uid-x" && !$0.isInput })
    }

    func testKnownDevicesSortedByLastSeenThenNameAndPersisted() throws {
        let now = Date()
        let devices = [
            StoredDevice(uid: "uid-1", name: "Zulu", isInput: true, lastSeen: now.addingTimeInterval(-60)),
            StoredDevice(uid: "uid-2", name: "alpha", isInput: true, lastSeen: now.addingTimeInterval(-60)),
            StoredDevice(uid: "uid-3", name: "Bravo", isInput: true, lastSeen: now)
        ]

        let data = try JSONEncoder().encode(devices)
        defaults.set(data, forKey: "knownDevices")
        defaults.set(false, forKey: "knownDevicesDeduped")

        let known = manager.getKnownDevices()
        XCTAssertEqual(known.map { $0.uid }, ["uid-3", "uid-2", "uid-1"])

        let persistedData = defaults.data(forKey: "knownDevices")
        XCTAssertNotNil(persistedData)
        let persisted = try JSONDecoder().decode([StoredDevice].self, from: persistedData!)
        XCTAssertEqual(persisted.map { $0.uid }, ["uid-3", "uid-2", "uid-1"])
    }

    func testGetKnownDevicesDoesNotClearDataOnDecodeFailure() {
        let badData = Data("not-json".utf8)
        defaults.set(badData, forKey: "knownDevices")

        let known = manager.getKnownDevices()

        XCTAssertTrue(known.isEmpty)
        XCTAssertEqual(defaults.data(forKey: "knownDevices"), badData)
    }

    func testRememberDevicePromotesMostRecent() throws {
        let now = Date()
        let devices = [
            StoredDevice(uid: "uid-1", name: "Older", isInput: true, lastSeen: now.addingTimeInterval(-3600)),
            StoredDevice(uid: "uid-2", name: "Oldest", isInput: true, lastSeen: now.addingTimeInterval(-7200))
        ]

        let data = try JSONEncoder().encode(devices)
        defaults.set(data, forKey: "knownDevices")
        defaults.set(true, forKey: "knownDevicesDeduped")

        manager.rememberDevice("uid-2", name: "Oldest", isInput: true)

        let known = manager.getKnownDevices()
        XCTAssertEqual(known.first?.uid, "uid-2")
    }
}
