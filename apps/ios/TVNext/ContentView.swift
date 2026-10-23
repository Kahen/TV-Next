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
    @StateObject private var library = MediaLibraryStore()
    @AppStorage("tv-next-api-url") private var serverURL = "http://localhost:8080"
    @State private var danmaku: [DanmakuComment] = []
    @State private var danmakuOptions = DanmakuOptions()
    @State private var remoteResourceKey: String?
    @State private var remoteDanmaku: [NativePlaybackResource] = []
    @State private var choosingDanmaku = false
    @State private var manualURL = ""
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
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    playerSection
                    quickPlaySection
                    localMediaSection
                    importSection
                    ConfigPreviewSection()
                    CloudSection(serverURL: serverURL) { library.play($0) }
                    SubscriptionSection(serverURL: serverURL, onPlay: { playback, title in
                        guard playback.headers.isEmpty else {
                            errorMessage = "此来源需要额外播放请求头，尚需服务端媒体适配。"
                            return
                        }
                        library.play(TVChannel(name: title + " · " + playback.name, url: playback.url, group: playback.lineName, logo: nil, tvgId: nil))
                        remoteResourceKey = playback.url
                        remoteDanmaku = playback.danmaku
                    }, onImport: { library.importChannels($0) })
                    MediaCatalogSection { channel in
                        errorMessage = nil
                        captionFileName = nil
                        library.play(channel)
                    }
                    danmakuSection
                    librarySection

                    Text("本地播放列表、收藏及进度只保存在这台设备；暂不支持跨设备同步。不内置媒体源。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 850)
                .frame(maxWidth: .infinity)
                .padding()
            }
            .navigationTitle("TV-Next")
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
                library.savePosition()
                library.player.pause()
            }
        }
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

    private var playerSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                VideoPlayer(player: library.player)
                    .frame(minHeight: 215)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
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

                HStack {
                    Text(library.localFileName ?? library.current?.name ?? "尚未选择媒体")
                        .font(.headline)
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
                if let issue = library.playbackError { Text(issue).font(.caption).foregroundStyle(.red) }
                Picker("播放速度", selection: $playbackSpeed) {
                    Text("0.75×").tag(Float(0.75))
                    Text("1×").tag(Float(1))
                    Text("1.25×").tag(Float(1.25))
                    Text("1.5×").tag(Float(1.5))
                    Text("2×").tag(Float(2))
                }
                .pickerStyle(.menu)
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
            HStack {
                TextField("https://example.org/movie.m3u8", text: $manualURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                Button("播放") {
                    let url = manualURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard MediaAddress.valid(url) else {
                        errorMessage = "请输入有效的 HTTP(S) 媒体地址。"
                        return
                    }
                    errorMessage = nil
                    captionFileName = nil
                    library.play(TVChannel(name: "自定义播放地址", url: url,
                                           group: "Manual", logo: nil, tvgId: nil))
                }
                .buttonStyle(.borderedProminent)
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
                        Label("导入 SRT / WebVTT 字幕", systemImage: "captions.bubble")
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
                    .font(.system(.footnote, design: .monospaced))
                    .frame(height: 120)
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
                    Task { await importPlaylist() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
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
                .pickerStyle(.segmented)

                TextField("按频道名称或分组搜索", text: $search)
                    .textFieldStyle(.roundedBorder)

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

                            Button {
                                library.toggleFavorite(channel)
                            } label: {
                                Image(systemName: library.isFavorite(channel) ? "star.fill" : "star")
                                    .foregroundStyle(.yellow)
                            }
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
                }
            }
            .padding(.top, 8)
        }
    }

    @MainActor
    private func importPlaylist() async {
        isLoading = true
        defer { isLoading = false }
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
            library.importChannels(channels)
            selection = .channels
            search = ""
            errorMessage = channels.isEmpty ? "没有找到 HTTP(S) 频道。" : nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func importLocalMedia(_ result: Result<[URL], Error>) async {
        isLoadingMedia = true
        defer { isLoadingMedia = false }
        do {
            guard let source = try result.get().first else { return }
            let localFile = try await LocalMediaStager.stage(source)
            library.playLocalFile(localFile, name: source.lastPathComponent)
            captionFileName = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importCaption(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            guard ["srt", "vtt"].contains(url.pathExtension.lowercased()) else {
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
