import XCTest
@testable import SkyWayClient

final class SkyWayClientTests: XCTestCase {
    func testExample() throws {
        // XCTest Documentation
        // https://developer.apple.com/documentation/xctest

        // Defining Test Cases and Test Methods
        // https://developer.apple.com/documentation/xctest/defining_test_cases_and_test_methods
        
        // Ensure RoomManager can be instantiated
        let manager = RoomManager()
        XCTAssertFalse(manager.isJoined)
    }
}
