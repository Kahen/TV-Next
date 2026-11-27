import XCTest
@testable import TVNext

final class NativeSMBShareAddressTests: XCTestCase {
    func testValidShareAndNestedUnicodePath() {
        let root = NativeSMBShareAddress.parse("smb://nas.local/Movies")
        XCTAssertEqual(root?.host, "nas.local")
        XCTAssertEqual(root?.port, 445)
        XCTAssertEqual(root?.share, "Movies")
        XCTAssertEqual(root?.components, [])
        let nested = NativeSMBShareAddress.parse("smb://192.168.1.20:1445/%E5%BD%B1%E8%A7%86/Season%202")
        XCTAssertEqual(nested?.port, 1445)
        XCTAssertEqual(nested?.share, "影视")
        XCTAssertEqual(nested?.components, ["Season 2"])
    }

    func testRejectsCredentialsAndNonSMBSchemes() {
        for value in ["https://nas.local/Movies", "smb://user:pass@nas.local/Movies",
                      "smb://user@nas.local/Movies", "smb://nas.local",
                      "smb://nas.local/Movies?token=secret",
                      "smb://nas.local/Movies#fragment", "smb://nas.local:0/Movies"] {
            XCTAssertNil(NativeSMBShareAddress.parse(value), value)
        }
    }

    func testRejectsTraversalAndAmbiguousSeparators() {
        for value in ["smb://nas.local/Movies/../Private",
                      "smb://nas.local/Movies/%2e%2e",
                      "smb://nas.local/Movies/%252e%252e",
                      "smb://nas.local/Movies/%2fPrivate",
                      "smb://nas.local/Movies/%5cPrivate",
                      "smb://nas.local/Movies//Episode",
                      "smb://nas.local/Movies/%00bad"] {
            XCTAssertNil(NativeSMBShareAddress.parse(value), value)
        }
    }

    func testInvalidDecodedHostCharacters() {
        for host in ["file%20server", "file%2Fserver", "file%5Cserver", "file%40server"] {
            XCTAssertNil(NativeSMBShareAddress.parse("smb://\(host)/share"))
        }
    }
}
