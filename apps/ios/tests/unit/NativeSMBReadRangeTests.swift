import XCTest
@testable import TVNext

final class NativeSMBReadRangeTests: XCTestCase {
    func testValidStartAndFinalByte() {
        let start = NativeSMBReadRange(offset: 0, length: 1024, fileSize: 1024)
        XCTAssertEqual(start?.offset, 0)
        XCTAssertEqual(start?.length, 1024)
        let finalByte = NativeSMBReadRange(offset: 1023, length: 1, fileSize: 1024)
        XCTAssertEqual(finalByte?.offset, 1023)
        XCTAssertEqual(finalByte?.length, 1)
    }

    func testRejectsInvalidBoundsAndOversizedChunks() {
        XCTAssertNil(NativeSMBReadRange(offset: -1, length: 1, fileSize: 10))
        XCTAssertNil(NativeSMBReadRange(offset: 0, length: 0, fileSize: 10))
        XCTAssertNil(NativeSMBReadRange(offset: 0, length: 1, fileSize: 0))
        XCTAssertNil(NativeSMBReadRange(offset: 10, length: 1, fileSize: 10))
        XCTAssertNil(NativeSMBReadRange(offset: 9, length: 2, fileSize: 10))
        XCTAssertNil(NativeSMBReadRange(offset: 0, length: 1_048_577, fileSize: 2_000_000))
        XCTAssertNil(NativeSMBReadRange(offset: Int64.max - 1, length: 10, fileSize: Int64.max))
    }

    func testAcceptsMaximumChunkWithoutOverflow() {
        XCTAssertNotNil(NativeSMBReadRange(offset: 0, length: 1_048_576, fileSize: Int64.max))
    }
}
