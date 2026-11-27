import XCTest
@testable import TVNext

final class NativeSMBDirectoryPageTests: XCTestCase {
    func testDirectoriesFirstAndNaturalOrdering() {
        let entries = [
            NativeSMBDirectoryEntry(name: "movie10.mp4", isDirectory: false, size: 10)!,
            NativeSMBDirectoryEntry(name: "Season 2", isDirectory: true, size: 0)!,
            NativeSMBDirectoryEntry(name: "movie2.mp4", isDirectory: false, size: 2)!
        ]
        XCTAssertEqual(NativeSMBDirectoryPage.normalize(entries)?.map(\.name),
                       ["Season 2", "movie2.mp4", "movie10.mp4"])
    }

    func testRejectsTraversalAndPathSeparators() {
        for name in [".", "..", "../secret", "folder\\child", "a/b", "a:b", "bad\nname", "bad\u{202E}name", "trailing."] {
            XCTAssertNil(NativeSMBDirectoryEntry(name: name, isDirectory: false, size: 1))
        }
    }

    func testValidUnicodeAndSizeBoundaries() {
        XCTAssertNotNil(NativeSMBDirectoryEntry(name: "电影 01.mkv", isDirectory: false, size: Int64.max))
        XCTAssertNil(NativeSMBDirectoryEntry(name: "file", isDirectory: false, size: -1))
        XCTAssertNil(NativeSMBDirectoryEntry(name: "dir", isDirectory: true, size: 1))
        XCTAssertNil(NativeSMBDirectoryEntry(name: String(repeating: "a", count: 256), isDirectory: false, size: 0))
    }

    func testRejectsAmbiguousDuplicateAndOversizedPage() {
        let a = NativeSMBDirectoryEntry(name: "Movie.mkv", isDirectory: false, size: 1)!
        let b = NativeSMBDirectoryEntry(name: "movie.mkv", isDirectory: false, size: 2)!
        XCTAssertNil(NativeSMBDirectoryPage.normalize([a, b]))
        XCTAssertNil(NativeSMBDirectoryPage.normalize(Array(repeating: a, count: 513)))
        XCTAssertEqual(NativeSMBDirectoryPage.normalize([]), [])

        let plain = NativeSMBDirectoryEntry(name: "Resume.mkv", isDirectory: false, size: 1)!
        let accented = NativeSMBDirectoryEntry(name: "Résumé.mkv", isDirectory: false, size: 2)!
        XCTAssertEqual(NativeSMBDirectoryPage.normalize([plain, accented])?.count, 2)
    }
}
