import XCTest
@testable import TVNext

final class NativeFongMiPageJumpTests: XCTestCase {
    func testValidPages() {
        XCTAssertEqual(NativeFongMiPageJump.parse("1"), 1)
        XCTAssertEqual(NativeFongMiPageJump.parse(" 42 "), 42)
        XCTAssertEqual(NativeFongMiPageJump.parse("10000"), 10_000)
        XCTAssertEqual(NativeFongMiPageJump.parse("00001"), 1)
    }

    func testInvalidPages() {
        for input in ["", " ", "0", "-1", "+2", "10001", "999999999999999999999",
                      "1.0", "1e2", "１２", "١", "1/2"] {
            XCTAssertNil(NativeFongMiPageJump.parse(input), "Should reject: \(input)")
        }
    }
}
