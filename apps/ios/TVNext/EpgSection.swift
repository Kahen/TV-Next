import SwiftUI
import UniformTypeIdentifiers

struct EpgSection: View {
    let serverURL: String
    let session: NativeHomeSession?
    let channels: [TVChannel]
    let onPlay: (TVChannel)->Void
    @State private var xml=""
    @State private var name=""
    @State private var url=""
    @State private var interval=360
    @State private var feeds: [NativeEpgFeed]=[]
    @State private var guide: NativeEpgGuide?
    @State private var snapshot: [TVChannel]=[]
    @State private var showingFile=false
    @State private var busy=false
    @State private var error: String?
    @State private var task: Task<Void,Never>?
    @State private var generation=UUID()
    var body: some View {
        GroupBox("直播节目表 · XMLTV") {
            VStack(alignment:.leading,spacing:12) {
                Text("先导入 M3U。按 tvg-id 优先匹配，最多 300 个频道；点击后播放所对应的频道。")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text:$xml).frame(height:90).border(.secondary).accessibilityLabel("XMLTV 内容")
                HStack {
                    Button("选择 XMLTV 文件") { showingFile=true }
                    Button("解析节目表") { loadGuide(nil) }.disabled(busy || channels.isEmpty || xml.isEmpty)
                }.buttonStyle(.bordered)
                if session != nil { subscriptionControls }
                else { Text("登录家庭服务器后可保存节目表订阅并定时刷新。").font(.caption) }
                if busy { ProgressView() }
                if let error { Text(error).foregroundStyle(.red).font(.caption) }
                guideResults
            }
        }
        .fileImporter(isPresented:$showingFile,allowedContentTypes:[.xml,.plainText],allowsMultipleSelection:false) { result in
            do {
                guard let file=try result.get().first else { return }
                let access=file.startAccessingSecurityScopedResource();defer { if access { file.stopAccessingSecurityScopedResource() } }
                let handle=try FileHandle(forReadingFrom:file);defer { try? handle.close() }
                let data=try handle.read(upToCount:2_097_153) ?? Data()
                guard !data.isEmpty,data.count<=2_097_152,let text=String(data:data,encoding:.utf8) else { throw NativeRequestError.message("XMLTV 必须是 1 B 至 2 MiB 的 UTF-8 文件") }
                invalidate();xml=text
            } catch { self.error=error.localizedDescription }
        }
        .onChange(of:channels) { _,_ in invalidate() }
        .onChange(of:xml) { _,_ in invalidate() }
        .onDisappear { task?.cancel();generation=UUID() }
    }
    private var subscriptionControls: some View {
        VStack(alignment:.leading,spacing:10) {
            TextField("节目表名称",text:$name).textFieldStyle(.roundedBorder)
            TextField("XMLTV / XMLTV.gz 订阅网址",text:$url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
            Picker("刷新间隔",selection:$interval) {
                Text("15 分钟").tag(15);Text("1 小时").tag(60);Text("6 小时").tag(360);Text("24 小时").tag(1440)
            }
            HStack {
                Button("保存订阅") {
                    let payload=NativeEpgFeedWrite(name:name,url:url,intervalMinutes:interval)
                    run { api in let _: NativeEpgFeed=try await api.request("home/epg/feeds",body:payload);return try await api.get("home/epg/feeds") } receive: { (value:[NativeEpgFeed]) in feeds=value;name="";url="" }
                }.disabled(busy || name.isEmpty || url.isEmpty)
                Button("读取订阅") { reload() }.disabled(busy)
            }.buttonStyle(.bordered)
            ForEach(feeds) { feed in
                VStack(alignment:.leading) {
                    Text(feed.name).font(.headline)
                    Text(feed.updatedAt>0 ? "缓存于 "+Date(timeIntervalSince1970:Double(feed.updatedAt)/1000).formatted() : "尚未下载").font(.caption)
                    if let issue=feed.lastError { Text(issue).font(.caption).foregroundStyle(.orange) }
                    HStack {
                        Button("立即刷新") { mutate(feed,"refresh") }
                        Button("显示节目表") { loadGuide(feed) }.disabled(!feed.available || channels.isEmpty)
                        Button("删除订阅") { mutate(feed,"remove") }
                    }.disabled(busy).buttonStyle(.bordered)
                }
            }
        }
    }
    @ViewBuilder private var guideResults: some View {
        if let guide {
            Text("已匹配 \(guide.matchedChannels) / \(guide.totalChannels)")
            ForEach(Array(guide.channels.enumerated()),id:\.offset) { index,channel in
                VStack(alignment:.leading,spacing:6) {
                    HStack {
                        Text(channel.name).font(.headline)
                        if snapshot.indices.contains(index) { Button("播放频道") { onPlay(snapshot[index]) } }
                    }
                    if let current=channel.current { Text("正在播："+current.title+" · "+current.range) }
                    ForEach(Array(channel.upcoming.enumerated()),id:\.offset) { _,program in
                        Text(program.range+" · "+program.title).font(.caption)
                    }
                }.padding(.vertical,6)
            }
            ForEach(Array(guide.warnings.enumerated()),id:\.offset) { _,warning in Text(warning).font(.caption) }
        }
    }
    private func invalidate() { task?.cancel();generation=UUID();busy=false;guide=nil;snapshot=[] }
    private func reload() {
        run { api in try await api.get("home/epg/feeds") } receive: { (value:[NativeEpgFeed]) in feeds=value }
    }
    private func mutate(_ feed: NativeEpgFeed,_ action: String) {
        run { api in
            if action=="refresh" { let _: NativeEpgFeed=try await api.request("home/epg/feeds/"+feed.id+"/refresh",body:EmptyHomeRequest()) }
            else { let _: [String:Bool]=try await api.request("home/epg/feeds/"+feed.id+"/remove",body:EmptyHomeRequest()) }
            return try await api.get("home/epg/feeds")
        } receive: { (value:[NativeEpgFeed]) in feeds=value;guide=nil;snapshot=[] }
    }
    private func loadGuide(_ feed: NativeEpgFeed?) {
        let entries=Array(channels.prefix(300))
        guard feed != nil || (!xml.isEmpty && xml.utf8.count<=2_097_152) else { error="XMLTV 内容超过 2 MiB";return }
        let payload=NativeEpgRequest(xml:feed==nil ? xml:nil,channels:entries.map { NativeEpgChannelRequest(id:$0.tvgId,name:$0.name) })
        guide=nil;snapshot=[]
        run { api in try await api.request(feed.map { "home/epg/feeds/"+$0.id+"/guide" } ?? "epg/guide",body:payload) } receive: { (value:NativeEpgGuide) in guide=value;snapshot=entries }
    }
    private func run<T>(_ operation: @escaping (TVNextAPI) async throws -> T,receive: @escaping (T)->Void) {
        task?.cancel();let id=UUID();generation=id;busy=true;error=nil
        task=Task { @MainActor in
            defer { if generation==id { busy=false } }
            do {
                guard let server=URL(string:serverURL) else { throw APIError.invalidServer }
                let value=try await operation(TVNextAPI(server:server,token:session?.token))
                try Task.checkCancellation();guard generation==id else { return };receive(value)
            } catch { if generation==id && !Task.isCancelled { self.error=error.localizedDescription } }
        }
    }
}
