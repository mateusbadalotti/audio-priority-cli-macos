import XCTest
@testable import AudioPriorityCore

final class IdentifierResolverTests: XCTestCase {
    func testSplitIdentifiersTrimsAndSplitsCommas() {
        let resolver = IdentifierResolver()
        let identifiers = resolver.splitIdentifiers(["1, 2", " 3 "])

        XCTAssertEqual(identifiers, ["1", "2", "3"])
    }

    func testResolveUIDsUsesIndexes() throws {
        let resolver = IdentifierResolver()
        let devices = [
            AudioDevice(id: 1, uid: "uid-1", name: "A", type: .output),
            AudioDevice(id: 2, uid: "uid-2", name: "B", type: .output),
        ]

        let uids = try resolver.resolveUIDs(type: .output, identifiers: ["2", "1"], devices: devices)

        XCTAssertEqual(uids, ["uid-2", "uid-1"])
    }

    func testResolveUIDsThrowsForInvalidIndex() {
        let resolver = IdentifierResolver()
        let devices = [
            AudioDevice(id: 1, uid: "uid-1", name: "A", type: .output),
        ]

        XCTAssertThrowsError(try resolver.resolveUIDs(type: .output, identifiers: ["2"], devices: devices)) { error in
            guard case let IdentifierResolutionError.invalidIndex(index, max, type) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
            XCTAssertEqual(index, 2)
            XCTAssertEqual(max, 1)
            XCTAssertEqual(type, .output)
        }
    }

    func testResolveUIDsRejectsNonNumericIdentifier() {
        let resolver = IdentifierResolver()
        let devices = [
            AudioDevice(id: 1, uid: "uid-1", name: "A", type: .output),
        ]

        XCTAssertThrowsError(try resolver.resolveUIDs(type: .output, identifiers: ["abc"], devices: devices)) { error in
            guard case let IdentifierResolutionError.nonNumeric(value) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
            XCTAssertEqual(value, "abc")
        }
    }
}
