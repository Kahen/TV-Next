import SwiftUI
import AVKit
import UniformTypeIdentifiers

private enum LibraryView: String, CaseIterable, Identifiable {
    case channels = "全部频道"
    case favorites = "收藏"
    case recent = "最近播放"

    var id: String { rawValue }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingFullscreen = false
    @StateObject private var library = MediaLibraryStore()
    @StateObject private var remote = NativeRemoteControl()
    @AppStorage("tv-next-api-url") private var serverURL = "http://localhost:8080"
    @State private var homeSession: NativeHomeSession?
    @State private var danmaku: [DanmakuComment] = []
    @State private var danmakuOptions = DanmakuOptions()
    @State private var remoteResourceKey: String?
    @State private var remoteDanmaku: [NativePlaybackResource] = []
    @State private var choosingDanmaku = false
    @State private var manualURL = ""
    @State private var quickPlayError: String?
    @State private var playlistText = ""
    @State private var search = ""
    @State private var selection: LibraryView = .channels
    @State private var useRemoteParser = false
    @State private var isShowingFilePicker = false
    @State private var isShowingMediaPicker = false
    @State private var isShowingCaptionPicker = false
    @State private var isLoadingMedia = false
    @State private var captionFileName: String?
    @State private var captionOffsetSeconds: Double = 0
    @State private var isShowingExporter = false
    @State private var exportDocument: M3UExportDocument?
    @State private var playbackSpeed: Float = 1.0
    @State private var isShowingClearConfirmation = false
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var importGeneration = UUID()
    @State private var mediaGeneration = UUID()

    private var visibleChannels: [TVChannel] {
        let entries: [TVChannel]
        switch selection {
        case .channels:
            entries = library.channels
        case .favorites:
            let available = library.channels + library.recent
            entries = library.favorites.compactMap { favorite in
                available.first(where: { $0.url == favorite })
            }
        case .recent:
            entries = library.recent
        }
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { channel in
            term.isEmpty ||
            channel.name.localizedCaseInsensitiveContains(term) ||
            channel.group.localizedCaseInsensitiveContains(term)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    playerSection.id("player")
                    quickPlaySection.id("quick-play")
                    localMediaSection.id("local-media")
                    importSection.id("import")
                    HomeServerSection(serverURL:$serverURL,library:library,onSessionChange:{ homeSession=$0;remote.configure($0,server:$1);library.configureRelay(server:$1,session:$0) },remoteState:remote.state)
                    EpgSection(serverURL:serverURL,session:homeSession,channels:library.channels) { library.play($0) }
                        .id(serverURL+"|"+(homeSession?.token ?? ""))
                    ConfigPreviewSection().id("config")
                    CloudSection(serverURL: serverURL) { library.play($0) }
                    SubscriptionSection(serverURL: serverURL, session:homeSession, onPlay: { playback, title in
                        library.play(TVChannel(name: title + " · " + playback.name, url: playback.url, group: playback.lineName, logo: nil, tvgId: nil, headers:playback.headers))
                        remoteResourceKey = playback.url
                        remoteDanmaku = playback.danmaku
                    }, onImport: { library.importChannels($0) })
                    MediaCatalogSection { channel in
                        errorMessage = nil
                        captionFileName = nil
                        library.play(channel)
                    }
                    danmakuSection
                    librarySection.id("library")

                    Text("本地媒体库保存在这台设备；登录家庭服务器后可主动同步。不内置媒体源。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 850)
                .frame(maxWidth: .infinity)
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("TV-Next")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("播放器") { proxy.scrollTo("player", anchor: .top) }
                        Button("快速播放") { proxy.scrollTo("quick-play", anchor: .top) }
                        Button("本机文件与字幕") { proxy.scrollTo("local-media", anchor: .top) }
                        Button("导入播放列表") { proxy.scrollTo("import", anchor: .top) }
                        Button("JSON 配置") { proxy.scrollTo("config", anchor: .top) }
                        Button("媒体库") { proxy.scrollTo("library", anchor: .top) }
                    } label: { Label("功能导航", systemImage: "line.3.horizontal") }
                    .accessibilityIdentifier("section-navigation")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") { dismissKeyboard() }
                }
            }
            .fullScreenCover(isPresented: $showingFullscreen) {
                ZStack(alignment: .topTrailing) {
                    Color.black.ignoresSafeArea()
                    playbackSurface
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Button { showingFullscreen = false } label: {
                        Label("退出全屏", systemImage: "xmark.circle.fill")
                            .padding().background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding()
                    .accessibilityIdentifier("exit-fullscreen")
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .inactive { library.savePosition() }
                if phase == .background {
                    mediaGeneration = UUID()
                    isLoadingMedia = false
                    library.suspendPlayback()
                    remote.configure(nil, server: serverURL)
                } else if phase == .active {
                    remote.configure(homeSession, server: serverURL)
                }
            }
            .onAppear {
                remote.receive = { packet in
                    switch packet.type {
                    case "LOAD":
                        guard let url=packet.url,MediaAddress.valid(url) else { throw NativeRequestError.message("媒体地址无效") }
                        library.play(TVChannel(name:"远程媒体",url:url,group:"Remote",logo:nil,tvgId:nil))
                    case "PLAY":
                        guard library.player.currentItem != nil else { throw NativeRequestError.message("尚未选择媒体") }
                        library.player.playImmediately(atRate:library.playbackSpeed)
                    case "PAUSE": library.player.pause()
                    case "SEEK":
                        guard let position=packet.position,position.isFinite,position>=0,let duration=library.player.currentItem?.duration.seconds,duration.isFinite,position<=duration else { throw NativeRequestError.message("媒体无法跳转到该位置") }
                        library.player.seek(to:CMTime(seconds:position,preferredTimescale:600))
                    default: throw NativeRequestError.message("未知遥控操作")
                    }
                }
            }
            .fileImporter(
                isPresented: $isShowingFilePicker,
                allowedContentTypes: [.plainText, UTType(filenameExtension: "m3u") ?? .plainText],
                allowsMultipleSelection: false
            ) { result in
                importFile(result)
            }
            .fileImporter(
                isPresented: $isShowingMediaPicker,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                Task { await importLocalMedia(result) }
            }
            .fileImporter(
                isPresented: $isShowingCaptionPicker,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                importCaption(result)
            }
            .fileExporter(
                isPresented: $isShowingExporter,
                document: exportDocument,
                contentType: .m3uPlaylist,
                defaultFilename: "tv-next-playlist"
            ) { result in
                if case .failure(let issue) = result {
                    errorMessage = issue.localizedDescription
                }
            }
            .confirmationDialog(
                "确定删除本机保存的播放列表、收藏和观看进度吗？",
                isPresented: $isShowingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("删除本地媒体库", role: .destructive) {
                    importGeneration = UUID()
                    mediaGeneration = UUID()
                    isLoading = false
                    isLoadingMedia = false
                    library.clear()
                    playlistText = ""
                    search = ""
                }
            }
            .fileImporter(isPresented: $choosingDanmaku, allowedContentTypes: [.xml, .json], allowsMultipleSelection: false) { result in
                do {
                    guard let file = try result.get().first else { return }
                    let access = file.startAccessingSecurityScopedResource()
                    defer { if access { file.stopAccessingSecurityScopedResource() } }
                    let handle = try FileHandle(forReadingFrom: file)
                    defer { try? handle.close() }
                    let data = try handle.read(upToCount: 2_097_153) ?? Data()
                    guard data.count <= 2_097_152, let text = String(data: data, encoding: .utf8) else { throw DanmakuError.invalid }
                    danmaku = try DanmakuParser.parse(text)
                } catch { errorMessage = error.localizedDescription }
            }
            .onChange(of: library.current?.url) { _, url in danmaku = []; if url != remoteResourceKey { remoteDanmaku = [] } }
            .onDisappear {
                // Presenting fullscreen keeps the same selected item and overlay state.
                guard !showingFullscreen else { return }
                remote.configure(nil,server:serverURL)
                library.suspendPlayback()
            }
            }
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private var danmakuSection: some View {
        GroupBox("弹幕 · \(danmaku.count) 条") {
            VStack(alignment: .leading) {
                Button("导入 XML / JSON 弹幕") { choosingDanmaku = true }.buttonStyle(.bordered)
                ForEach(remoteDanmaku) { resource in
                    Button("加载 " + resource.name) {
                        let key = library.current?.url
                        Task { @MainActor in
                            do {
                                guard let url = URL(string: serverURL) else { throw APIError.invalidServer }
                                let result: NativeTextResponse = try await TVNextAPI(server: url).request("resources/text", body: NativeResourceRequest(url: resource.url))
                                guard library.current?.url == key else { return }
                                danmaku = try DanmakuParser.parse(result.content)
                            } catch { errorMessage = error.localizedDescription }
                        }
                    }
                }
                Toggle("显示弹幕", isOn: $danmakuOptions.enabled)
                HStack { Text("透明度"); Slider(value: $danmakuOptions.opacity, in: 0.1...1) }
                HStack { Text("字号"); Slider(value: $danmakuOptions.fontSize, in: 12...40, step: 1) }
                HStack { Text("显示区域"); Slider(value: $danmakuOptions.area, in: 0.25...1, step: 0.25) }
                HStack { Text("时长"); Slider(value: $danmakuOptions.duration, in: 4...15, step: 1) }
                HStack { Text("偏移 \(Int(danmakuOptions.offset)) 秒"); Slider(value: $danmakuOptions.offset, in: -120...120, step: 1) }
                TextField("屏蔽词，逗号分隔", text: $danmakuOptions.blocked).textFieldStyle(.roundedBorder)
                Button("清空弹幕") { danmaku = [] }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("PERSONAL MEDIA").font(.caption2).tracking(3).foregroundStyle(.secondary)
            Text("你的媒体，随处播放。").font(.largeTitle).fontWeight(.bold)
            Text("iPhone / iPad · M3U · 收藏 · 点播断点续播")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var playbackSurface: some View {
        VideoPlayer(player: library.player)
                    .background(Color.black)
                    .overlay(alignment: .bottom) {
                        if !library.captionText.isEmpty {
                            Text(library.captionText)
                                .font(.headline)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 6))
                                .padding(.horizontal, 12)
                                .padding(.bottom, 32)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay { DanmakuOverlay(player: library.player, comments: danmaku, options: danmakuOptions).padding(.bottom, 44) }
                    .clipShape(RoundedRectangle(cornerRadius: 12))

    }

    private var playerSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                playbackSurface
                    .frame(minHeight: 215)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                Button("全屏播放", systemImage: "arrow.up.left.and.arrow.down.right") {
                    dismissKeyboard()
                    showingFullscreen = true
                }
                .disabled(library.player.currentItem == nil)
                .accessibilityIdentifier("enter-fullscreen")

                HStack {
                    Text(library.localFileName ?? library.current?.name ?? "尚未选择媒体")
                        .font(.headline)
                        .accessibilityIdentifier("current-media")
                    .accessibilityLabel("正在播放：" + (library.localFileName ?? library.current?.name ?? "尚未选择媒体"))
                    Spacer()
                    if let channel = library.current {
                        Button {
                            library.toggleFavorite(channel)
                        } label: {
                            Label(
                                library.isFavorite(channel) ? "取消收藏" : "收藏",
                                systemImage: library.isFavorite(channel) ? "star.fill" : "star"
                            )
                        }
                        .buttonStyle(.bordered)
                    }
                }
                if let issue = library.playbackError {
                    Text(issue).font(.caption).foregroundStyle(.red)
                        .accessibilityIdentifier("playback-error")
                    Button("重试播放") { library.retryPlayback() }
                        .accessibilityIdentifier("retry-playback")
                }
                Picker("播放速度", selection: $playbackSpeed) {
                    Text("0.75×").tag(Float(0.75))
                    Text("1×").tag(Float(1))
                    Text("1.25×").tag(Float(1.25))
                    Text("1.5×").tag(Float(1.5))
                    Text("2×").tag(Float(2))
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("playback-speed")
                .onChange(of: playbackSpeed) { _, speed in
                    library.setPlaybackSpeed(speed)
                }

                if let channel = library.current,
                   let seconds = library.positions[channel.url] {
                    Text("已记住播放进度：" + String(Int(seconds / 60)) + " 分钟")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var quickPlaySection: some View {
        GroupBox("快速播放") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("https://example.org/movie.m3u8", text: $manualURL)
                    .accessibilityLabel("媒体地址")
                    .accessibilityIdentifier("manual-url")
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                Button("播放") {
                    dismissKeyboard()
                    let url = manualURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard MediaAddress.valid(url) else {
                        quickPlayError = "请输入有效的 HTTP(S) 媒体地址。"
                        return
                    }
                    quickPlayError = nil
                    errorMessage = nil
                    captionFileName = nil
                    library.play(TVChannel(name: "自定义播放地址", url: url,
                                           group: "Manual", logo: nil, tvgId: nil))
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("play-url")
                if let quickPlayError {
                    Text(quickPlayError).foregroundStyle(.red)
                        .accessibilityIdentifier("quick-play-error")
                }
            }
            .padding(.top, 8)
        }
    }

    private var localMediaSection: some View {
        GroupBox("本机文件与字幕") {
            VStack(alignment: .leading, spacing: 12) {
                Text("本机视频仅保存在临时缓存，不上传、不加入历史。支持 MP4/MOV/M4V 及常见音频，最大 2 GiB；编解码能力取决于设备。")
                    .font(.footnote).foregroundStyle(.secondary)
                Button {
                    isShowingMediaPicker = true
                } label: {
                    Label(isLoadingMedia ? "正在导入…" : "打开本地视频 / 音频", systemImage: "film")
                }
                .buttonStyle(.bordered)
                .disabled(isLoadingMedia)
                HStack {
                    Button {
                        isShowingCaptionPicker = true
                    } label: {
                        Label("导入 SRT / VTT / ASS / SSA 字幕", systemImage: "captions.bubble")
                    }
                    .buttonStyle(.bordered)
                    if captionFileName != nil {
                        Button("移除字幕") {
                            library.clearCaptions()
                            captionFileName = nil
                            captionOffsetSeconds = 0
                        }.buttonStyle(.bordered)
                    }
                }
                if let captionFileName {
                    Text("字幕：" + captionFileName)
                        .font(.caption).foregroundStyle(.secondary)
                    Slider(value: $captionOffsetSeconds, in: -10...10, step: 0.5) {
                        Text("字幕偏移")
                    }
                    .onChange(of: captionOffsetSeconds) { _, offset in
                        library.setCaptionOffset(offset)
                    }
                    Text("字幕偏移：" + String(format: "%.1f", captionOffsetSeconds) + " 秒（正值延后）")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)
        }
    }

    private var importSection: some View {
        GroupBox("导入 M3U 播放列表") {
            VStack(alignment: .leading, spacing: 12) {
                Text("默认直接在 iPhone/iPad 本机解析，不必部署服务器。导入会替换当前频道，但保留收藏和观看记录。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    isShowingFilePicker = true
                } label: {
                    Label("选择本地 M3U / TXT 文件", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)

                TextEditor(text: $playlistText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.footnote, design: .monospaced))
                    .frame(height: 120)
                    .accessibilityLabel("M3U 内容")
                    .accessibilityIdentifier("playlist-input")
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray.opacity(0.3)))

                Toggle("使用自建 API 解析", isOn: $useRemoteParser)
                    .font(.subheadline)

                if useRemoteParser {
                    TextField("API 地址", text: $serverURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                    Text("真机使用可访问的 HTTPS 服务。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if !library.channels.isEmpty {
                    Button {
                        exportDocument = M3UExportDocument(channels: library.channels)
                        isShowingExporter = true
                    } label: {
                        Label("导出当前播放列表 (.m3u)", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }

                Button(isLoading ? "解析中…" : "导入频道") {
                    dismissKeyboard()
                    Task { await importPlaylist() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)
                .accessibilityIdentifier("import-playlist")
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .accessibilityIdentifier("import-error")
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
            .padding(.top, 8)
        }
    }

    private var librarySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Picker("媒体库", selection: $selection) {
                    ForEach(LibraryView.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("library-collection")

                TextField("按频道名称或分组搜索", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("library-search")

                if visibleChannels.isEmpty {
                    Text(selection == .favorites ? "还没有收藏的频道。" :
                            selection == .recent ? "还没有播放记录。" : "请先导入播放列表。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(visibleChannels) { channel in
                        HStack(spacing: 12) {
                            Button {
                                errorMessage = nil
                                captionFileName = nil
                                library.play(channel)
                            } label: {
                                HStack {
                                    Image(systemName: "play.circle")
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(channel.name)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                        Text(channel.group)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("播放 " + channel.name)
                            .accessibilityIdentifier("channel-" + channel.name)
                            .accessibilityAddTraits(library.current?.url == channel.url ? .isSelected : [])

                            Button {
                                library.toggleFavorite(channel)
                            } label: {
                                Image(systemName: library.isFavorite(channel) ? "star.fill" : "star")
                                    .foregroundStyle(.yellow)
                            }
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityIdentifier("favorite-" + channel.name)
                            .accessibilityLabel(library.isFavorite(channel) ?
                                "取消收藏 " + channel.name : "收藏 " + channel.name)
                            .buttonStyle(.plain)
                        }
                        Divider()
                    }
                }

                if !library.channels.isEmpty || !library.recent.isEmpty {
                    Button("清空本地媒体库", role: .destructive) {
                        isShowingClearConfirmation = true
                    }
                    .font(.footnote)
                    .accessibilityIdentifier("clear-library")
                }
            }
            .padding(.top, 8)
        }
    }

    @MainActor
    private func importPlaylist() async {
        let generation = UUID()
        importGeneration = generation
        isLoading = true
        defer { if importGeneration == generation { isLoading = false } }
        do {
            let channels: [TVChannel]
            if useRemoteParser {
                guard let server = URL(string: serverURL) else {
                    throw APIError.invalidServer
                }
                channels = try await TVNextAPI(server: server).parsePlaylist(playlistText)
            } else {
                channels = try M3UParser.parse(playlistText)
            }
            guard importGeneration == generation else { return }
            guard library.importChannels(channels) else {
                errorMessage = "未找到可播放的 HTTP(S) 频道，已保留原有媒体库。"
                return
            }
            selection = .channels
            search = ""
            errorMessage = channels.isEmpty ? "没有找到 HTTP(S) 频道。" : nil
        } catch {
            if importGeneration == generation { errorMessage = error.localizedDescription }
        }
    }

    @MainActor
    private func importLocalMedia(_ result: Result<[URL], Error>) async {
        let generation = UUID()
        mediaGeneration = generation
        isLoadingMedia = true
        defer { if mediaGeneration == generation { isLoadingMedia = false } }
        do {
            guard let source = try result.get().first else { return }
            let localFile = try await LocalMediaStager.stage(source)
            guard mediaGeneration == generation else { LocalMediaStager.discard(localFile); return }
            library.playLocalFile(localFile, name: source.lastPathComponent)
            captionFileName = nil
            errorMessage = nil
        } catch {
            if mediaGeneration == generation { errorMessage = error.localizedDescription }
        }
    }

    private func importCaption(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            guard ["srt", "vtt", "ass", "ssa"].contains(url.pathExtension.lowercased()) else {
                throw CaptionError.invalidTimeline
            }
            let permission = url.startAccessingSecurityScopedResource()
            defer { if permission { url.stopAccessingSecurityScopedResource() } }
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attributes[.size] as? NSNumber, size.int64Value > 1_048_576 {
                throw CaptionError.tooLarge
            }
            let cues = try CaptionParser.parse(Data(contentsOf: url))
            library.setCaptions(cues)
            captionOffsetSeconds = 0
            captionFileName = url.lastPathComponent
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importFile(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            let canAccess = url.startAccessingSecurityScopedResource()
            defer { if canAccess { url.stopAccessingSecurityScopedResource() } }
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attrs[.size] as? NSNumber, size.intValue > 1_048_576 {
                throw PlaylistError.tooLarge
            }
            playlistText = try String(contentsOf: url, encoding: .utf8)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ContentView()
}
