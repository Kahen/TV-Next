import Foundation

@main struct NativeActionRetrySmoke {
    static func main() {
        let context = NativeActionRetryContext(
            siteKey: "demo", action: "login", subscriptionContent: "{\"sites\":[]}",
            subscriptionURL: "https://example.org/config.json"
        )
        precondition(context != nil)
        precondition(context!.matches(
            siteKey: "demo", subscriptionContent: "{\"sites\":[]}",
            subscriptionURL: "https://example.org/config.json"
        ))
        precondition(!context!.matches(
            siteKey: "other", subscriptionContent: "{\"sites\":[]}",
            subscriptionURL: "https://example.org/config.json"
        ))
        precondition(!context!.matches(
            siteKey: "demo", subscriptionContent: "changed",
            subscriptionURL: "https://example.org/config.json"
        ))
        precondition(!context!.matches(
            siteKey: "demo", subscriptionContent: "{\"sites\":[]}",
            subscriptionURL: "https://example.org/other.json"
        ))
        precondition(NativeActionRetryContext(
            siteKey: "", action: "login", subscriptionContent: "", subscriptionURL: ""
        ) == nil)
        precondition(NativeActionRetryContext(
            siteKey: "demo", action: "bad\nrequest", subscriptionContent: "", subscriptionURL: ""
        ) == nil)
        precondition(NativeActionRetryContext(
            siteKey: "demo", action: String(repeating: "x", count: 4097),
            subscriptionContent: "", subscriptionURL: ""
        ) == nil)
        print("Native action retry context: PASS")
    }
}
