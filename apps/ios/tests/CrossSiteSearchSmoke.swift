import Foundation

private actor RequestCounter {
    var active = 0
    var peak = 0
    var calls: [String] = []
    func begin(_ value: String) { active += 1; peak = max(peak, active); calls.append(value) }
    func end() { active -= 1 }
    func snapshot() -> (Int, [String]) { (peak, calls) }
}

@main struct CrossSiteSearchSmoke {
    struct Item { let id: String }
    static func main() async throws {
        let sources = (0..<6).map { NativeSearchSource(key: String($0), name: "Source \($0)") }
        let counter = RequestCounter()
        let result = try await NativeCrossSiteSearch.search(sources: sources, fetch: { source, page in
            await counter.begin("\(source.key):\(page)")
            try await Task.sleep(for: .milliseconds(source.key == "0" ? 10 : 3))
            await counter.end()
            if source.key == "0" && page == 1 { return NativeSearchPage(items: [Item(id:"shared")], hasMore:true) }
            if source.key == "0" { return NativeSearchPage(items:[Item(id:"shared"),Item(id:"next")],hasMore:false) }
            if source.key == "1" { throw NSError(domain:"secret token",code:1) }
            return NativeSearchPage(items:[Item(id:"shared")],hasMore:false)
        }, identity: { $0.id })
        precondition(result.items.map { "\($0.siteKey):\($0.item.id)" } == ["0:shared","0:next","2:shared","3:shared","4:shared","5:shared"])
        precondition(result.failed == ["Source 1"])
        precondition(!String(describing:result.failed).contains("secret"))
        let (peak, calls) = await counter.snapshot()
        precondition(peak > 1 && peak <= 4, "Concurrent site count outside 2...4")
        precondition(calls.contains("0:2"))

        let bounded = try await NativeCrossSiteSearch.search(sources:(0..<20).map { NativeSearchSource(key:String($0),name:String($0)) }, fetch: { source, page in
            NativeSearchPage(items:[Item(id:"\(source.key)-\(page)")],hasMore:true)
        }, identity: { $0.id })
        precondition(bounded.items.count == 32)
        precondition(bounded.warnings.count == 2)
        precondition(!bounded.items.contains(where:{$0.siteKey == "16"}))
        let duplicates = try await NativeCrossSiteSearch.search(sources:[sources[0],sources[0]],fetch:{ _,_ in
            NativeSearchPage(items:[Item(id:""),Item(id:"x"),Item(id:"x")],hasMore:false)
        },identity:{$0.id})
        precondition(duplicates.items.count == 1)
        let capped = try await NativeCrossSiteSearch.search(sources:(0..<16).map { NativeSearchSource(key:String($0),name:String($0)) },fetch:{ source,page in
            NativeSearchPage(items:(0..<50).map { Item(id:"\(source.key)-\(page)-\($0)") },hasMore:true)
        },identity:{$0.id})
        precondition(capped.items.count == 600)
        precondition(capped.warnings.contains(where:{$0.contains("600")}))
        let task = Task { try await NativeCrossSiteSearch.search(sources:sources,fetch:{ _,_ in
            try await Task.sleep(for:.seconds(3))
            return NativeSearchPage(items:[Item(id:"stale")],hasMore:false)
        },identity:{$0.id}) }
        task.cancel()
        do { _ = try await task.value; fatalError("Cancellation was ignored") } catch is CancellationError {}
        print("Native cross-provider search: ordering, concurrency, bounds, failures, duplicates and cancellation passed")
    }
}
