import SwiftUI

/// Explicit renderer control URL instead of silently discovering/controlling LAN devices.
/// Nothing entered here is persisted or sent to the TV-Next home server.
struct NativeDLNASection: View {
    @ObservedObject var library: MediaLibraryStore
    @State private var rendererAddress = ""
    @State private var mediaAddress = ""
    @State private var status: String?
    @State private var error: String?
    @State private var busy = false
    @State private var castStarted = false
    @State private var task: Task<Void, Never>?

    private var endpoint: URL? { try? NativeDLNA.rendererURL(rendererAddress) }
    private var media: URL? { try? NativeDLNA.mediaURL(mediaAddress) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DLNA 局域网投屏（手动）").font(.headline)
            Text("输入设备的 AVTransport 控制地址和设备能直接访问的媒体 URL。当前版本不自动搜索设备，也不转发请求头或私有媒体。")
                .font(.caption).foregroundStyle(.secondary)
            TextField("http://192.168.1.20:1400/MediaRenderer/AVTransport/Control", text: $rendererAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .keyboardType(.URL).textContentType(.URL)
                .accessibilityIdentifier("dlna-renderer-url")
                .onChange(of: rendererAddress) { _, _ in reset() }
            TextField("https://media.example/owned.mp4", text: $mediaAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .keyboardType(.URL).textContentType(.URL)
                .accessibilityIdentifier("dlna-media-url")
                .onChange(of: mediaAddress) { _, _ in reset() }
            Button("使用当前播放地址") {
                guard let current = library.current,
                      (current.headers ?? [:]).isEmpty,
                      current.headersRequired != true, current.replay == nil,
                      (try? NativeDLNA.mediaURL(current.url)) != nil else { return }
                mediaAddress = current.url
            }
            .disabled(busy || library.current == nil ||
                      !(library.current?.headers ?? [:]).isEmpty ||
                      library.current?.headersRequired == true || library.current?.replay != nil)
            .accessibilityIdentifier("dlna-use-current")
            HStack(spacing: 12) {
                Button("投屏播放") { run(.setURI) }
                    .disabled(busy || endpoint == nil || media == nil)
                    .accessibilityIdentifier("dlna-cast")
                Button("暂停") { run(.pause) }
                    .disabled(busy || endpoint == nil || !castStarted)
                    .accessibilityIdentifier("dlna-pause")
                Button("停止") { run(.stop) }
                    .disabled(busy || endpoint == nil || !castStarted)
                    .accessibilityIdentifier("dlna-stop")
            }
            Button("查询设备播放状态") { run(.getTransportInfo) }
                .disabled(busy || endpoint == nil)
                .accessibilityIdentifier("dlna-query-state")
            Button("查询播放进度") { run(.getPositionInfo) }
                .disabled(busy || endpoint == nil)
                .accessibilityIdentifier("dlna-query-position")
            HStack(spacing: 12) {
                Button("快退15秒") { runSeek(-NativeDLNASeek.stepSeconds) }
                    .disabled(busy || endpoint == nil)
                    .accessibilityIdentifier("dlna-seek-back")
                Button("快进15秒") { runSeek(NativeDLNASeek.stepSeconds) }
                    .disabled(busy || endpoint == nil)
                    .accessibilityIdentifier("dlna-seek-forward")
            }
            Text("跳转前会重新查询设备状态和有限媒体时长；不支持直播或未知时长。")
                .font(.caption).foregroundStyle(.secondary)
            if busy { ProgressView("正在等待 DLNA 设备…") }
            if let status { Text(status).accessibilityIdentifier("dlna-status") }
            if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("dlna-error") }
            Text("仅支持手动填写的私有 IPv4 HTTP 控制端点（含端口）；投屏 URL 必须由电视直接获取。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onDisappear {
            task?.cancel()
            task = nil
            busy = false
        }
    }

    private func reset() {
        task?.cancel()
        task = nil
        busy = false
        castStarted = false
        status = nil
        error = nil
    }

    private func runSeek(_ deltaSeconds: Int) {
        guard !busy, let endpoint else { return }
        busy = true
        status = nil
        error = nil
        task = Task { @MainActor in
            do {
                let target = try await NativeDLNA.seekRelative(endpoint: endpoint, deltaSeconds: deltaSeconds)
                guard !Task.isCancelled else { return }
                status = "已请求跳转至：" + (try NativeDLNASeek.target(target))
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
            if !Task.isCancelled { busy = false }
        }
    }

    private func run(_ action: NativeDLNAAction) {
        guard !busy, let endpoint else { return }
        let media = self.media
        if action == .setURI && media == nil { return }
        busy = true
        status = nil
        error = nil
        task = Task { @MainActor in
            do {
                if action == .setURI {
                    try await NativeDLNA.cast(endpoint: endpoint, media: media!)
                } else if action == .getTransportInfo {
                    let state = try await NativeDLNA.queryState(endpoint: endpoint)
                    guard !Task.isCancelled else { return }
                    castStarted = state.canControlPlayback
                    status = "设备状态：\(state.localizedLabel)"
                } else if action == .getPositionInfo {
                    let position = try await NativeDLNA.queryPosition(endpoint: endpoint)
                    guard !Task.isCancelled else { return }
                    status = "设备进度：\(position.localizedLabel)"
                } else {
                    try await NativeDLNA.send(action, endpoint: endpoint)
                }
                guard !Task.isCancelled else { return }
                if action == .setURI { castStarted = true; status = "投屏已开始" }
                if action == .pause { status = "已发送暂停命令" }
                if action == .stop { castStarted = false; status = "已发送停止命令" }
            } catch {
                guard !Task.isCancelled else { return }
                castStarted = false
                self.error = error.localizedDescription
            }
            if !Task.isCancelled { busy = false }
        }
    }
}
