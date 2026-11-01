import SwiftUI

struct SubscriptionSection: View {
    let serverURL: String
    var session: NativeHomeSession? = nil
    let onPlay: (NativeMediaPlayback, String) -> Void
    var onImport: (([TVChannel]) -> Void)? = nil
    @State private var address = ""
    @State private var content = ""
    @State private var rememberURL = false
    @State private var document: NativeSubscription?
    @State private var siteKey = ""
    @State private var query = ""
    @State private var page: NativeMediaPage?
    @State private var mode = "home"
    @State private var category: String?
    @State private var filterCatalog: [String:[NativeSiteFilter]]=[:]
    @State private var filters: [String:String]=[:]
    @State private var appliedFilters: [String:String]=[:]
    @State private var actionResult: NativeSubscriptionAction?
    @State private var detail: NativeMediaDetail?
    @State private var crossSiteResults: [NativeSearchHit<NativeMediaItem>] = []
    @State private var crossSiteFailures: [String] = []
    @State private var crossSiteFailedKeys: [String] = []
    @State private var crossSiteSearchKeyword: String?
    @State private var crossSiteSourceOrder: [String] = []
    @State private var crossSiteSourceNames: [String: String] = [:]
    @State private var crossSiteWarnings: [String] = []
    @State private var line = 0
    @State private var error: String?
    @State private var busy = false
    @State private var pending: Task<Void,Never>?
    @State private var generation = UUID()

    var body: some View {
        GroupBox("TVBox / FongMi 原版订阅") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("订阅 URL / 相对路径基准", text: $address).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                TextEditor(text: $content).frame(height: 100).font(.system(.footnote, design: .monospaced)).accessibilityLabel("订阅配置内容")
                Toggle("记住订阅地址（仅 URL，存入本机钥匙串）", isOn: $rememberURL)
                    .onChange(of: rememberURL) { _, enabled in
                        if !enabled && !NativeSubscriptionURLStore().clear() {
                            // A failed delete must not silently imply that a secret was erased.
                            rememberURL = true
                            error = "钥匙串删除失败，订阅地址仍可能保留。请稍后重试。"
                        }
                    }
                Button("清除保存的订阅地址") {
                    if NativeSubscriptionURLStore().clear() {
                        rememberURL = false
                        address = ""
                    } else {
                        error = "钥匙串删除失败，订阅地址仍可能保留。请稍后重试。"
                    }
                }.buttonStyle(.bordered).accessibilityIdentifier("clear-saved-subscription-url")
                Text("粘贴的配置正文不会保存；只有开启记住且使用订阅 URL 成功加载后，才保存地址。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("加载订阅") { load() }.buttonStyle(.borderedProminent).disabled(busy)
                    if busy { Button("取消") { pending?.cancel(); generation = UUID(); busy = false } }
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                if let actionResult { actionView(actionResult) }
                if let document { documentView(document) }
                if let page { pageView(page) }
                if !crossSiteFailures.isEmpty {
                    Text("以下站点未完成搜索：" + crossSiteFailures.joined(separator: "、"))
                        .font(.caption).foregroundStyle(.orange)
                    Button("重试失败站点（\(crossSiteFailedKeys.count)）") { retryFailedSites() }
                        .buttonStyle(.bordered)
                        .disabled(busy || crossSiteFailedKeys.isEmpty)
                        .accessibilityIdentifier("retry-failed-cross-site-search")
                }
                ForEach(crossSiteWarnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                if !crossSiteResults.isEmpty {
                    LazyVStack(alignment: .leading) {
                        Text("跨站搜索结果").font(.headline)
                        ForEach(crossSiteResults.indices, id: \.self) { index in
                            let hit = crossSiteResults[index]
                            Button(hit.item.name + " · " + (crossSiteSourceNames[hit.siteKey] ?? hit.siteKey)) {
                                inspect(hit.item, from: hit.siteKey)
                            }.disabled(busy).padding(.vertical, 4)
                        }
                    }
                }
                if let detail { detailView(detail) }
            }
        }
        .onAppear {
            if address.isEmpty, let stored = NativeSubscriptionURLStore().read() {
                address = stored
                rememberURL = true
            }
        }
        .onDisappear { pending?.cancel(); actionResult = nil; clearCrossSiteSearch() }
        .onChange(of:serverURL) { _,_ in pending?.cancel();generation=UUID();busy=false;document=nil;page=nil;detail=nil;actionResult=nil;filterCatalog=[:];filters=[:];appliedFilters=[:];category=nil;siteKey="";clearCrossSiteSearch() }
        .onChange(of:session?.token) { _,_ in pending?.cancel();generation=UUID();busy=false;actionResult=nil;clearCrossSiteSearch() }
    }
    private func run(_ operation: @escaping (TVNextAPI, UUID) async throws -> Void) {
        pending?.cancel()
        let id = UUID(); generation = id; busy = true; error = nil; actionResult = nil
        pending = Task { @MainActor in
            do {
                guard let url = URL(string: serverURL) else { throw APIError.invalidServer }
                try await operation(TVNextAPI(server: url,token:session?.token),id)
            } catch { if generation == id && !Task.isCancelled { self.error = error.localizedDescription } }
            if generation == id { busy = false }
        }
    }
    private func clearCrossSiteSearch() {
        crossSiteResults = []; crossSiteFailures = []; crossSiteFailedKeys = []
        crossSiteSearchKeyword = nil; crossSiteSourceOrder = []; crossSiteSourceNames = [:]; crossSiteWarnings = []
    }
    private func switchDetailSite(_ key: String) {
        var scope = NativeSiteBrowsingContext(
            siteKey: siteKey, category: category, mode: mode,
            filterCatalog: filterCatalog, filters: filters, appliedFilters: appliedFilters
        )
        if scope.switchToDetailSite(key) {
            siteKey = scope.siteKey; category = scope.category; mode = scope.mode
            filterCatalog = scope.filterCatalog; filters = scope.filters
            appliedFilters = scope.appliedFilters; page = nil
        }
    }
    private func load(_ url: String? = nil) {
        let targetURL = url ?? address
        let inlineContent = url == nil ? content : ""
        let shouldSaveURL = rememberURL && inlineContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        run { api, id in
            let result: NativeSubscription = try await api.request("subscriptions/load", body: NativeSubscriptionRequest(content: inlineContent, url: targetURL))
            guard generation == id, !Task.isCancelled else { return }
            document = result; page = nil; detail = nil; siteKey = "";filterCatalog=[:];filters=[:];appliedFilters=[:];category=nil;clearCrossSiteSearch()
            // URL is only saved after a successful, current-generation remote load.
            // Never save pasted configurations or a URL on a failed/canceled request.
            if shouldSaveURL && rememberURL && !NativeSubscriptionURLStore().save(targetURL) {
                error = "订阅已加载，但无法安全保存地址。请检查 URL 和钥匙串权限。"
            }
        }
    }
    private func request(_ key: String? = nil) -> NativeSiteRequest {
        var r = NativeSiteRequest(); r.content = document?.content ?? ""; r.url = document?.url ?? ""
        r.siteKey = key ?? siteKey; r.categoryId = category; r.query = query;r.filters=appliedFilters
        return r
    }
    private func browse(_ key: String, operation: String = "home", number: Int = 1, type: String? = nil, selectedFilters: [String:String]? = nil,bypassCache: Bool=false) {
        let same=key==siteKey
        let wasSameCategory = same && (type ?? category)==category && mode=="category"
        let nextCategory=type ?? category
        let choices=operation != "category" ? [:] : selectedFilters ?? (same && nextCategory==category && mode=="category" ? appliedFilters : NativeSiteFilter.defaults((same ? filterCatalog:[:])[nextCategory ?? ""] ?? []))
        var r = request(key); r.page = number; r.categoryId = nextCategory;r.filters=choices;r.bypassCache=bypassCache
        run { api, id in
            let result: NativeMediaPage = try await api.request("subscriptions/" + operation, body: r)
            guard generation == id, !Task.isCancelled else { return }
            page = result; detail = nil; siteKey = key; mode = operation; category = operation=="home" ? nil:r.categoryId;clearCrossSiteSearch()
            filterCatalog=same ? filterCatalog.merging(result.filters ?? [:],uniquingKeysWith:{ _,new in new }):result.filters ?? [:]
            appliedFilters=operation=="category" ? choices:[:]
            // Keep unsaved Picker edits local; paging uses only the last applied values.
            if operation != "category" || number == 1 || !wasSameCategory {
                filters=operation=="category" ? choices:[:]
            }
        }
    }
    private func searchAll() {
        guard let document else { return }
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        let sources = document.sites.filter { $0.searchable && !$0.hidden && $0.supported && ($0.type != 3 || session != nil) }
            .map { NativeSearchSource(key: $0.key, name: $0.name) }
        clearCrossSiteSearch(); page = nil; detail = nil
        guard !sources.isEmpty else {
            crossSiteWarnings = ["当前订阅没有可搜索的已授权站点。"]
            return
        }
        crossSiteSearchKeyword = keyword
        let selected = NativeCrossSiteSearch.selectedSources(sources)
        crossSiteSourceOrder = selected.map(\.key)
        // Bind displayed provenance to the actual eligible providers, not
        // an earlier hidden/unsupported duplicate in the raw subscription.
        crossSiteSourceNames = NativeCrossSiteSearch.selectedSourceNames(selected)
        run { api, id in
            let result = try await NativeCrossSiteSearch.search(sources: sources, concurrency: document.sites.contains { $0.type == 3 && $0.supported } ? 2 : 4, fetch: { source, number in
                var r = NativeSiteRequest()
                r.content = document.content; r.url = document.url
                r.siteKey = source.key; r.query = keyword; r.page = number
                let response: NativeMediaPage = try await api.request("subscriptions/search", body: r)
                return NativeSearchPage(items: response.items, hasMore: response.hasMore)
            }, identity: { $0.id })
            guard generation == id, !Task.isCancelled else { return }
            crossSiteResults = result.items
            crossSiteFailures = result.failed
            crossSiteFailedKeys = result.failedKeys
            crossSiteWarnings = result.warnings
        }
    }

    /// Retry only failed provider keys, using the original submitted keyword
    /// even if the text field has since changed. Never reuse a display name
    /// for routing: multiple providers may share the same visible name.
    private func retryFailedSites() {
        guard let document, let keyword = crossSiteSearchKeyword,
              !crossSiteFailedKeys.isEmpty else { return }
        let eligible = document.sites.filter {
            $0.searchable && !$0.hidden && $0.supported && ($0.type != 3 || session != nil)
        }.map { NativeSearchSource(key: $0.key, name: $0.name) }
        let sources = NativeCrossSiteSearch.failedOnlySources(eligible, failedKeys: crossSiteFailedKeys)
        guard !sources.isEmpty else { return }
        let sourceOrder = crossSiteSourceOrder
        run { api, id in
            let retry = try await NativeCrossSiteSearch.search(
                sources: sources,
                concurrency: sources.contains { key in document.sites.contains { $0.key == key.key && $0.type == 3 } } ? 2 : 4,
                fetch: { source, number in
                    var r = NativeSiteRequest()
                    r.content = document.content; r.url = document.url
                    r.siteKey = source.key; r.query = keyword; r.page = number
                    let response: NativeMediaPage = try await api.request("subscriptions/search", body: r)
                    return NativeSearchPage(items: response.items, hasMore: response.hasMore)
                },
                identity: { $0.id }
            )
            guard generation == id, !Task.isCancelled else { return }
            let recovered = Set(sources.map(\.key)).subtracting(retry.failedKeys)
            crossSiteResults = NativeCrossSiteSearch.mergeRetry(
                previous: crossSiteResults, refreshed: retry.items,
                recoveredKeys: recovered, sourceOrder: sourceOrder,
                identity: { $0.id }
            )
            crossSiteFailures = retry.failed
            crossSiteFailedKeys = retry.failedKeys
            for warning in retry.warnings where !crossSiteWarnings.contains(warning) {
                crossSiteWarnings.append(warning)
            }
        }
    }
    private func loadLive(_ index: Int) {
        guard let document else { return }
        run { api, id in
            let result: NativeLiveResponse = try await api.request("subscriptions/live",body:NativeLiveRequest(content:document.content,url:document.url,liveIndex:index))
            guard generation == id, !Task.isCancelled else { return }
            onImport?(result.channels)
            if !result.warnings.isEmpty { error = result.warnings.joined(separator: " · ") }
        }
    }
    private func inspect(_ item: NativeMediaItem, from key: String? = nil) {
        let targetKey = key ?? siteKey
        if item.folder == true { browse(targetKey,operation:"category",type:item.id); return }
        if let action = item.action, !action.isEmpty {
            var r = request(targetKey); r.action = action
            run { api, id in
                let result: NativeSubscriptionAction = try await api.request("subscriptions/action",body:r)
                guard generation == id, !Task.isCancelled else { return }
                switchDetailSite(targetKey)
                detail = nil; actionResult = result
            }
            return
        }
        var r = request(targetKey); r.vodId = item.id
        run { api, id in
            let result: NativeMediaDetail = try await api.request("subscriptions/detail",body:r)
            guard generation == id, !Task.isCancelled else { return }
            switchDetailSite(targetKey)
            detail = result; line = 0
        }
    }
    private func play(_ index: Int) {
        guard let detail else { return }
        var r = request(); r.vodId = detail.item.id; r.lineIndex = line; r.episodeIndex = index
        run { api, id in
            let result: NativeMediaPlayback = try await api.request("subscriptions/play",body:r)
            guard generation == id, !Task.isCancelled else { return }
            onPlay(result, detail.item.name)
        }
    }
    @ViewBuilder private func actionView(_ result: NativeSubscriptionAction) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let message = result.message { Text(message).font(.callout) }
            if let link = result.link {
                Link("在外部浏览器打开站点网页", destination: link)
                    .accessibilityHint("会离开当前应用，不会自动登录或同步 Cookie")
            }
            if result.limitedBrowserFeatures {
                Text("原版内嵌视图或 Cookie 自动关闭尚未支持；仅手动打开外部浏览器，不同步凭据。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if result.unsupported {
                Text("站点返回了未支持的操作指令或不安全的网址，未执行。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .contain)
    }
    @ViewBuilder private func documentView(_ doc: NativeSubscription) -> some View {
        ForEach(0..<min(doc.liveCount,50),id: \.self) { index in
            Button("导入直播源 \(index + 1)") { loadLive(index) }.disabled(busy)
        }
        ForEach(doc.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
        ForEach(doc.depots) { depot in Button(depot.name) { load(depot.url) }.disabled(busy) }
        ScrollView(.horizontal) {
            HStack { ForEach(doc.sites.filter { !$0.hidden }) { site in
                Button(site.name + (site.supported ? (site.type == 3 && session == nil ? " · 请先登录" : "") : " · 需 Spider 适配")) { browse(site.key) }
                    .buttonStyle(.bordered).disabled(busy || !site.supported || (site.type == 3 && session == nil))
            } }
        }
        HStack {
            TextField("搜索当前站点",text:$query).textFieldStyle(.roundedBorder)
            Button("搜索") { browse(siteKey,operation:"search") }.disabled(busy || siteKey.isEmpty || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("跨站搜索") { searchAll() }.disabled(busy || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
    @ViewBuilder private func pageView(_ page: NativeMediaPage) -> some View {
        ScrollView(.horizontal) { HStack { ForEach(page.categories) { type in
            Button(type.name) { browse(siteKey,operation:"category",type:type.id) }.buttonStyle(.bordered).disabled(busy)
        } } }
        if mode=="category",let category,let entries=filterCatalog[category],!entries.isEmpty {
            VStack(alignment:.leading) {
                ForEach(entries) { filter in
                    Picker(filter.name.isEmpty ? filter.key:filter.name,selection:Binding(get:{ filters[filter.key] ?? filter.initial ?? "" },set:{ filters[filter.key]=$0 })) {
                        if !filter.value.contains(where:{ $0.v==(filters[filter.key] ?? filter.initial ?? "") }) { Text("默认").tag(filters[filter.key] ?? filter.initial ?? "") }
                        ForEach(filter.value,id:\.v) { value in Text(value.n.isEmpty ? (value.v.isEmpty ? "全部":value.v):value.n).tag(value.v) }
                    }.disabled(busy)
                }
                if entries.contains(where: { (filters[$0.key] ?? $0.initial ?? "") != (appliedFilters[$0.key] ?? $0.initial ?? "") }) {
                    Text("筛选尚未应用，翻页仍使用已应用条件").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("应用筛选") { browse(siteKey,operation:"category",number:1,type:category,selectedFilters:NativeSiteFilter.defaults(entries).merging(filters,uniquingKeysWith:{ _,new in new })) }
                    Button("重置筛选") { browse(siteKey,operation:"category",number:1,type:category,selectedFilters:NativeSiteFilter.defaults(entries)) }
                }.disabled(busy)
            }
        }
        LazyVStack(alignment: .leading) { ForEach(page.items) { item in
            Button(item.name + (item.remarks.map { " · " + $0 } ?? "")) { inspect(item) }.disabled(busy).padding(.vertical,5)
        } }
        if mode=="search",session != nil { Button("刷新搜索结果") { browse(siteKey,operation:"search",number:page.page,bypassCache:true) }.disabled(busy) }
        HStack {
            Button("上一页") { browse(siteKey,operation:mode,number:page.page-1) }.disabled(busy || page.page <= 1)
            Spacer(); Text("第 \(page.page) 页").font(.caption); Spacer()
            Button("下一页") { browse(siteKey,operation:mode,number:page.page+1) }.disabled(busy || !page.hasMore)
        }
    }
    @ViewBuilder private func detailView(_ detail: NativeMediaDetail) -> some View {
        Text(detail.item.name).font(.headline)
        if let text = detail.description { Text(text).font(.caption) }
        ScrollView(.horizontal) { HStack { ForEach(detail.lines.indices,id:\.self) { i in
            Button(detail.lines[i].name) { line = i }.buttonStyle(.bordered)
        } } }
        if detail.lines.indices.contains(line) {
            ForEach(detail.lines[line].episodes.indices,id:\.self) { i in
                let episode = detail.lines[line].episodes[i]
                Button(episode.name) { play(i) }.disabled(busy || !episode.playable)
            }
        }
    }
}
