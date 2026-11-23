import XCTest
@testable import TVNext

final class NativeSearchQuerySnapshotTests: XCTestCase {
    func testPagingPreservesCommittedQueryDespiteDraftEdits() {
        XCTAssertEqual(NativeSearchQuerySnapshot.resolve(draft: "new term", committed: "old term", reuseCommitted: true), "old term")
    }

    func testFreshSearchUsesTrimmedDraft() {
        XCTAssertEqual(NativeSearchQuerySnapshot.resolve(draft: "  新搜索  ", committed: "old", reuseCommitted: false), "新搜索")
    }

    func testDifferentSiteNeverReusesOldQuery() {
        XCTAssertEqual(NativeSearchQuerySnapshot.resolve(draft: "other", committed: "private", reuseCommitted: false), "other")
    }

    func testPreviousPageToFirstPageKeepsSubmittedQuery() {
        XCTAssertEqual(NativeSearchQuerySnapshot.resolve(draft: "edited", committed: "original", reuseCommitted: true), "original")
    }

    func testNoSnapshotFallsBackToDraft() {
        XCTAssertEqual(NativeSearchQuerySnapshot.resolve(draft: "fallback", committed: nil, reuseCommitted: true), "fallback")
    }

    func testEmptyCommittedQueryIsNotReplacedByNewDraft() {
        XCTAssertEqual(NativeSearchQuerySnapshot.resolve(draft: "changed", committed: "", reuseCommitted: true), "")
    }
}
