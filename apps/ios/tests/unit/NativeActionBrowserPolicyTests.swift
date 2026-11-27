import XCTest
@testable import TVNext

final class NativeActionBrowserPolicyTests: XCTestCase {
    func testAcceptsHTTPSAction() {
        let url = URL(string: "https://example.org/login?next=%2Fwatch")
        XCTAssertEqual(NativeActionBrowserPolicy.approvedURL(url), url)
    }

    func testRejectsUnsafeAndCredentialBearingActions() {
        for raw in [
            "http://example.org/login", "javascript:alert(1)",
            "file:///etc/passwd", "https://user:secret@example.org/login",
            "https://user@example.org/login", "data:text/html,hello",
            "https:///missing-host"
        ] {
            XCTAssertNil(NativeActionBrowserPolicy.approvedURL(URL(string: raw)), raw)
        }
        XCTAssertNil(NativeActionBrowserPolicy.approvedURL(nil))
    }
}
