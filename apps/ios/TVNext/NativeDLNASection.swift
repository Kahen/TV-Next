import SwiftUI

/// Explicit renderer control URL instead of silently discovering/controlling LAN devices.
/// Nothing entered here is persisted or sent to the TV-Next home server.
struct NativeDLNASection: View {
    @ObservedObject var library: MediaLibraryStore
    @State private var descriptionAddress = ""
    @State private var importedControlAddress: String?
    @State private var importedDeviceName: String?
    @State private var importedModelName: String?
    @State private var rendererAddress = ""
    @State private var mediaAddress = ""
    @State private var seekTime = ""
    @State private var status: String?
    @State private var error: String?
    @State private var busy = false
    @State private var castStarted = false
    @State private var paused = false
    @State private var task: Task<Void, Never>?

    private var endpoint: URL? { try? NativeDLNA.rendererURL(rendererAddress) }
    private var media: URL? { try? NativeDLNA.mediaURL(mediaAddress) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DLNA 局域网投屏（手动）").font(.headline)
            Text("输入设备的 AVTransport 控制地址和设备能直接访问的媒体 URL。当前版本不自动搜索设备，也不转发请求头或私有媒体。")
                .font(.caption).foregroundStyle(.secondary)
            TextField("http://192.168.1.20:1400/device.xml", text: $descriptionAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .keyboardType(.URL).textContentType(.URL)
                .accessibilityIdentifier("dlna-description-url")
                .onChange(of: descriptionAddress) { _, _ in
                    importedControlAddress = nil
                    importedDeviceName = nil
                    importedModelName = nil
                }
            Button("从设备描述导入控制地址") { importDescription() }
                .disabled(busy || (try? NativeDLNADescription.location(descriptionAddress)) == nil)
                .accessibilityIdentifier("dlna-import-description")
            Text("仅请求你明确填写的私有 IPv4 设备描述地址，不进行局域网扫描；只接受同设备同端口的 AVTransport:1 控制地址。")
                .font(.caption).foregroundStyle(.secondary)
            if let importedControlAddress, importedControlAddress == rendererAddress {
                Text("已导入控制地址：\(importedControlAddress)")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("dlna-imported-control")
                if let importedDeviceName {
                    Text("设备名称：\(importedDeviceName)")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("dlna-imported-name")
                }
                if let importedModelName {
                    Text("设备型号：\(importedModelName)")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("dlna-imported-model")
                }
            }
            TextField("http://192.168.1.20:1400/MediaRenderer/AVTransport/Control", text: $rendererAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .keyboardType(.URL).textContentType(.URL)
                .accessibilityIdentifier("dlna-renderer-url")
                .onChange(of: rendererAddress) { _, newValue in
                    reset()
                    if importedControlAddress != newValue {
                        importedControlAddress = nil
                        importedDeviceName = nil
                        importedModelName = nil
                    }
                }
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
            Button("继续播放") { run(.play) }
                .disabled(busy || endpoint == nil || !paused)
                .accessibilityIdentifier("dlna-resume")
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
            HStack(spacing: 12) {
                TextField("00:01:30", text: $seekTime)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("dlna-seek-time")
                Button("跳转到指定时间") { runAbsoluteSeek() }
                    .disabled(busy || endpoint == nil ||
                              (try? NativeDLNASeek.parseAbsolute(seekTime)) == nil)
                    .accessibilityIdentifier("dlna-seek-absolute")
            }
            Text("跳转前会重新查询设备状态和有限媒体时长；指定时间必须是 HH:MM:SS 且不超过总时长，不支持直播。")
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
        paused = false
        seekTime = ""
        status = nil
        error = nil
    }

    private func importDescription() {
        guard !busy, (try? NativeDLNADescription.location(descriptionAddress)) != nil else { return }
        let source = descriptionAddress
        importedControlAddress = nil
        importedDeviceName = nil
        importedModelName = nil
        busy = true
        status = nil
        error = nil
        task = Task { @MainActor in
            do {
                let imported = try await NativeDLNADescription.loadDetails(source)
                guard !Task.isCancelled else { return }
                guard descriptionAddress == source else {
                    busy = false
                    task = nil
                    return
                }
                // Clear the completed task before changing the renderer field:
                // its existing onChange reset must not cancel the importer.
                task = nil
                busy = false
                rendererAddress = imported.controlURL.absoluteString
                importedControlAddress = imported.controlURL.absoluteString
                importedDeviceName = imported.friendlyName
                importedModelName = imported.modelName
            } catch {
                guard !Task.isCancelled else { return }
                guard descriptionAddress == source else {
                    busy = false
                    task = nil
                    return
                }
                self.error = error.localizedDescription
                busy = false
                task = nil
            }
        }
    }

    private func runAbsoluteSeek() {
        guard !busy, let endpoint else { return }
        let targetText = seekTime
        guard (try? NativeDLNASeek.parseAbsolute(targetText)) != nil else { return }
        busy = true
        status = nil
        error = nil
        task = Task { @MainActor in
            do {
                let target = try await NativeDLNA.seekAbsolute(endpoint: endpoint, targetText: targetText)
                guard !Task.isCancelled else { return }
                status = "已请求跳转至：" + (try NativeDLNASeek.target(target))
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
            if !Task.isCancelled { busy = false }
        }
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
        if action == .play && !paused { return }
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
                    paused = state == .pausedPlayback
                    status = "设备状态：\(state.localizedLabel)"
                } else if action == .play {
                    try await NativeDLNA.resumePaused(endpoint: endpoint)
                } else if action == .getPositionInfo {
                    let position = try await NativeDLNA.queryPosition(endpoint: endpoint)
                    guard !Task.isCancelled else { return }
                    status = "设备进度：\(position.localizedLabel)"
                } else {
                    try await NativeDLNA.send(action, endpoint: endpoint)
                }
                guard !Task.isCancelled else { return }
                if action == .setURI { castStarted = true; paused = false; status = "投屏已开始" }
                if action == .pause { paused = true; status = "已发送暂停命令" }
                if action == .play { paused = false; status = "已发送继续播放命令" }
                if action == .stop { castStarted = false; paused = false; status = "已发送停止命令" }
            } catch {
                guard !Task.isCancelled else { return }
                castStarted = false
                paused = false
                self.error = error.localizedDescription
            }
            if !Task.isCancelled { busy = false }
        }
    }
}
