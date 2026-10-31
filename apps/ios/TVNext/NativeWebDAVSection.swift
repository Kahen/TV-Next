import SwiftUI

/// Native read-only WebDAV browser. Credentials are intentionally not persisted.
struct NativeWebDAVSection: View {
    let onPlay: (TVChannel) -> Void
    let onDisconnect: (URL) -> Void
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var connection: NativeWebDAVConnection?
    private var root: URL? { connection?.root }
    @State private var folder: URL?
    @State private var entries: [NativeWebDAVItem] = []
    @State private var filter = ""
    @State private var mediaOnly = false
    @State private var descending = false
    @State private var busy = false
    @State private var error: String?
    @State private var requestID = UUID()
    @State private var task: Task<Void, Never>?

    var body: some View {
        GroupBox("WebDAV · 只读文件浏览") {
            VStack(alignment: .leading, spacing: 12) {
                Text("仅连接你有权访问的 WebDAV。账号密码不保存；使用密码必须启用 HTTPS。受保护媒体播放需要先登录家庭服务器以使用安全媒体中继。")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("WebDAV 根目录 URL", text: $address)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder).accessibilityIdentifier("webdav-url")
                TextField("用户名（可选）", text: $username)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder).accessibilityIdentifier("webdav-user")
                SecureField("密码（可选）", text: $password)
                    .textFieldStyle(.roundedBorder).accessibilityIdentifier("webdav-password")
                HStack {
                    Button("连接 WebDAV") { connect() }
                        .disabled(busy || address.isEmpty)
                        .accessibilityIdentifier("webdav-connect")
                    Button("断开并清除凭据") { disconnect() }
                        .accessibilityIdentifier("webdav-disconnect")
                }.buttonStyle(.bordered)
                if busy { ProgressView("读取目录…") }
                if let error { Text(error).font(.caption).foregroundStyle(.red).accessibilityIdentifier("webdav-error") }
                if let root, let folder {
                    Text("已连接：" + (root.host ?? "") + "。修改地址或账号后需重新连接。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("当前目录：" + folder.path).font(.caption).textSelection(.enabled)
                    // Each shortcut is a validated ancestor URL, not a path
                    // reconstructed from a potentially untrusted filename.
                    let ancestors = NativeWebDAV.navigationPath(root: root, folder: folder)
                    if ancestors.count > 1 {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(ancestors, id: \.absoluteString) { ancestor in
                                    Button(ancestor == root ? "根目录" : ancestor.lastPathComponent) {
                                        open(ancestor)
                                    }
                                    .disabled(busy || ancestor == folder)
                                    .accessibilityIdentifier(ancestor == root ? "webdav-root" : "webdav-ancestor")
                                }
                            }
                        }
                    }
                    HStack {
                        Button("上级目录") { open(folder.deletingLastPathComponent()) }
                            .disabled(busy || folder == root)
                        Button("刷新当前目录") { open(folder) }
                            .disabled(busy)
                            .accessibilityIdentifier("webdav-refresh")
                    }
                    TextField("筛选当前目录文件名", text: $filter)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("webdav-filter")
                    Toggle("仅显示可播放文件（保留文件夹）", isOn: $mediaOnly)
                        .accessibilityIdentifier("webdav-media-only")
                    Button(descending ? "名称排序：降序" : "名称排序：升序") {
                        descending.toggle()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("webdav-sort")
                    let visible = NativeWebDAV.visibleEntries(entries, search: filter, mediaOnly: mediaOnly,
                                                               sortOrder: descending ? .descending : .ascending)
                    ForEach(visible) { entry in
                        HStack(spacing: 8) {
                            Button {
                                if entry.isDirectory { open(entry.url) } else { play(entry) }
                            } label: {
                                Label(entry.name, systemImage: entry.isDirectory ? "folder" : "play.circle")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .disabled(busy || (!entry.isDirectory && !NativeWebDAV.playable(entry)))
                            if !entry.isDirectory, let bytes = entry.sizeBytes {
                                Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .binary))
                                    .font(.caption).foregroundStyle(.secondary)
                                    .accessibilityIdentifier("webdav-size-\(entry.name)")
                            }
                            if let modified = entry.lastModified {
                                Text(modified, format: .dateTime.year().month().day().hour().minute())
                                    .font(.caption2).foregroundStyle(.secondary)
                                    .accessibilityIdentifier("webdav-modified-\(entry.name)")
                            }
                        }
                    }
                    if visible.isEmpty && !busy { Text("目录为空，或当前筛选没有匹配项。").font(.caption) }
                    Text("当前显示 \(visible.count)/\(entries.count) 项。")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text("最多读取并显示前 200 项；筛选不向服务器发送查询。")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .onDisappear { disconnect() }
    }

    private func connect() {
        // Changing servers also revokes any credentials retained by the player.
        if let root { onDisconnect(root) }
        task?.cancel()
        requestID = UUID()
        connection = nil
        folder = nil
        entries = []
        filter = ""
        mediaOnly = false
        descending = false
        busy = false
        error = nil
        do {
            let active = try NativeWebDAVConnection(address: address, username: username, password: password)
            connection = active
            open(active.root)
        } catch { self.error = error.localizedDescription }
    }

    private func open(_ next: URL) {
        guard let active = connection, NativeWebDAV.contains(next, root: active.root) else {
            error = NativeWebDAVError.invalidFolder.localizedDescription
            return
        }
        task?.cancel()
        let id = UUID()
        requestID = id
        busy = true
        error = nil
        task = Task { @MainActor in
            do {
                let result = try await active.list(folder: next)
                guard !Task.isCancelled, requestID == id else { return }
                if folder != next { filter = "" }
                folder = next
                entries = result
            } catch {
                if !Task.isCancelled && requestID == id { self.error = error.localizedDescription }
            }
            if requestID == id { busy = false }
        }
    }

    private func play(_ entry: NativeWebDAVItem) {
        guard let active = connection, NativeWebDAV.contains(entry.url, root: active.root),
              NativeWebDAV.playable(entry), MediaAddress.valid(entry.url.absoluteString) else {
            error = NativeWebDAVError.invalidFolder.localizedDescription
            return
        }
        do {
            let auth = try active.authorization(for: entry.url)
            let headers = auth.map { ["Authorization": $0] }
            onPlay(TVChannel(name: entry.name, url: entry.url.absoluteString,
                             group: "WebDAV", logo: nil, tvgId: nil, headers: headers))
        } catch { self.error = error.localizedDescription }
    }

    private func disconnect() {
        if let root { onDisconnect(root) }
        task?.cancel()
        task = nil
        requestID = UUID()
        connection = nil
        folder = nil
        entries = []
        filter = ""
        mediaOnly = false
        descending = false
        username = ""
        password = ""
        busy = false
        error = nil
    }
}
