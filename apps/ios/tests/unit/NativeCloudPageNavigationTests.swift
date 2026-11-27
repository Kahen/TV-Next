import XCTest
@testable import TVNext

final class NativeCloudPageNavigationTests: XCTestCase {
    func testValidPageTransitions() {
        XCTAssertEqual(NativeCloudPageNavigation.previous(2), 1)
        XCTAssertEqual(NativeCloudPageNavigation.next(1, hasMore: true), 2)
        XCTAssertEqual(NativeCloudPageNavigation.next(Int.max - 1, hasMore: true), Int.max)
    }

    func testRejectsInvalidAndTerminalPages() {
        XCTAssertNil(NativeCloudPageNavigation.previous(1))
        XCTAssertNil(NativeCloudPageNavigation.previous(0))
        XCTAssertNil(NativeCloudPageNavigation.previous(Int.min))
        XCTAssertNil(NativeCloudPageNavigation.next(0, hasMore: true))
        XCTAssertNil(NativeCloudPageNavigation.next(-1, hasMore: true))
        XCTAssertNil(NativeCloudPageNavigation.next(Int.max, hasMore: true))
        XCTAssertNil(NativeCloudPageNavigation.next(5, hasMore: false))
    }
}
