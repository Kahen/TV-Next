import SwiftUI

/// Native read-only WebDAV browser. Credentials are intentionally not persisted.
struct NativeWebDAVSection: View {
    let onPlay: (TVChannel) -> Void
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var root: URL?
    @State private var folder: URL?
    @State private var entries: [NativeWebDAVItem] = []
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
                    Text("当前目录：" + folder.path).font(.caption).textSelection(.enabled)
                    Button("上级目录") { open(folder.deletingLastPathComponent()) }
                        .disabled(busy || folder == root)
                    ForEach(entries) { entry in
                        Button {
                            if entry.isDirectory { open(entry.url) } else { play(entry) }
                        } label: {
                            Label(entry.name, systemImage: entry.isDirectory ? "folder" : "play.circle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .disabled(busy || (!entry.isDirectory && !NativeWebDAV.playable(entry)))
                    }
                    if entries.isEmpty && !busy { Text("目录为空，或没有可安全展示的文件。").font(.caption) }
                    Text("最多显示 200 项；仅可播放 AVPlayer 支持的媒体文件。")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .onDisappear { disconnect() }
    }

    private func connect() {
        task?.cancel()
        requestID = UUID()
        root = nil
        folder = nil
        entries = []
        busy = false
        error = nil
        do {
            let url = try NativeWebDAV.rootURL(address, username: username, password: password)
            root = url
            open(url)
        } catch { error = error.localizedDescription }
    }

    private func open(_ next: URL) {
        guard let root, NativeWebDAV.contains(next, root: root) else {
            error = NativeWebDAVError.invalidFolder.localizedDescription
            return
        }
        task?.cancel()
        let id = UUID()
        requestID = id
        busy = true
        error = nil
        let user = username
        let secret = password
        task = Task { @MainActor in
            do {
                let result = try await NativeWebDAV.list(root: root, folder: next, username: user, password: secret)
                guard !Task.isCancelled, requestID == id else { return }
                folder = next
                entries = result
            } catch {
                if !Task.isCancelled && requestID == id { self.error = error.localizedDescription }
            }
            if requestID == id { busy = false }
        }
    }

    private func play(_ entry: NativeWebDAVItem) {
        guard let root, NativeWebDAV.contains(entry.url, root: root),
              NativeWebDAV.playable(entry), MediaAddress.valid(entry.url.absoluteString) else {
            error = NativeWebDAVError.invalidFolder.localizedDescription
            return
        }
        do {
            let auth = try NativeWebDAV.authorization(username: username, password: password, root: root)
            let headers = auth.map { ["Authorization": $0] }
            onPlay(TVChannel(name: entry.name, url: entry.url.absoluteString,
                             group: "WebDAV", logo: nil, tvgId: nil, headers: headers))
        } catch { error = error.localizedDescription }
    }

    private func disconnect() {
        task?.cancel()
        task = nil
        requestID = UUID()
        root = nil
        folder = nil
        entries = []
        username = ""
        password = ""
        busy = false
        error = nil
    }
}
