import XCTest
@testable import TVNext

final class NativeActionRetryContextTests: XCTestCase {
    func testSameSubscriptionAndSiteCanRetry() {
        let context = NativeActionRetryContext(
            siteKey: "provider", action: "login", subscriptionContent: "config",
            subscriptionURL: "https://example.org/config"
        )
        XCTAssertNotNil(context)
        XCTAssertTrue(context!.matches(
            siteKey: "provider", subscriptionContent: "config",
            subscriptionURL: "https://example.org/config"
        ))
    }

    func testChangedSiteOrSubscriptionCannotRetry() {
        let context = NativeActionRetryContext(
            siteKey: "provider", action: "login", subscriptionContent: "config",
            subscriptionURL: "https://example.org/config"
        )!
        XCTAssertFalse(context.matches(siteKey: "other", subscriptionContent: "config",
                                       subscriptionURL: "https://example.org/config"))
        XCTAssertFalse(context.matches(siteKey: "provider", subscriptionContent: "changed",
                                       subscriptionURL: "https://example.org/config"))
        XCTAssertFalse(context.matches(siteKey: "provider", subscriptionContent: "config",
                                       subscriptionURL: "https://example.org/other"))
    }

    func testInvalidActionsAreRejected() {
        XCTAssertNil(NativeActionRetryContext(siteKey: "", action: "login",
                                              subscriptionContent: "", subscriptionURL: ""))
        XCTAssertNil(NativeActionRetryContext(siteKey: "provider", action: "bad\nrequest",
                                              subscriptionContent: "", subscriptionURL: ""))
        XCTAssertNil(NativeActionRetryContext(siteKey: "provider",
                                              action: String(repeating: "x", count: 4097),
                                              subscriptionContent: "", subscriptionURL: ""))
    }
}
