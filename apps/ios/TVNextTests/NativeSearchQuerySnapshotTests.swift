import XCTest
@testable import TVNext

final class NativeSearchQuerySnapshotTests: XCTestCase {
    func testPagingPreservesCommittedQueryDespiteDraftEdits() {
        XCTAssertEqual(NativeSearchQuerySnapshot.resolve(draft: "new term", committed: "old term", page: 2, sameSite: true), "old term")
    }

    func testFreshSearchUsesTrimmedDraft() {
        XCTAssertEqual(NativeSearchQuerySnapshot.resolve(draft: "  新搜索  ", committed: "old", page: 1, sameSite: true), "新搜索")
    }

    func testDifferentSiteNeverReusesOldQuery() {
        XCTAssertEqual(NativeSearchQuerySnapshot.resolve(draft: "other", committed: "private", page: 3, sameSite: false), "other")
    }

    func testNoSnapshotFallsBackToDraft() {
        XCTAssertEqual(NativeSearchQuerySnapshot.resolve(draft: "fallback", committed: nil, page: 2, sameSite: true), "fallback")
    }

    func testEmptyCommittedQueryIsNotReplacedByNewDraft() {
        XCTAssertEqual(NativeSearchQuerySnapshot.resolve(draft: "changed", committed: "", page: 2, sameSite: true), "")
    }
}
