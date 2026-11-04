import SwiftUI

struct NativeOfflineSection: View {
    @ObservedObject var downloads: NativeOfflineDownloads
    @ObservedObject var library: MediaLibraryStore
    @State private var address = ""
    @State private var name = ""
    @State private var pendingDeletion: NativeOfflineMediaEntry?

    private var storageUsage: String {
        let used = downloads.entries.reduce(Int64(0)) { $0 + $1.bytes }
        return "已保存 \(downloads.entries.count) / 20 个文件 · \(ByteCountFormatter.string(fromByteCount: used, countStyle: .file)) / 2 GiB"
    }

    var body: some View {
        GroupBox("离线媒体") {
            VStack(alignment: .leading, spacing: 12) {
                Text("只下载你有权保存的媒体直链；下载期间保持应用在前台并连接 Wi-Fi。已完成的文件可在无网络时播放，重启后保留。")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("媒体直链 URL", text: $address)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder).accessibilityIdentifier("offline-url")
                TextField("离线名称", text: $name)
                    .textFieldStyle(.roundedBorder).accessibilityIdentifier("offline-name")
                if let current = library.current,
                   current.replay == nil, current.headersRequired != true, (current.headers ?? [:]).isEmpty,
                   NativeOfflineMediaCatalog.sourceURL(current.url) != nil {
                    Button("填入当前媒体") { address = current.url; name = current.name }
                        .accessibilityIdentifier("offline-use-current")
                }
                Button("下载到本机") { downloads.start(address: address, name: name) }
                    .disabled(downloads.busy || address.isEmpty)
                    .buttonStyle(.bordered).accessibilityIdentifier("offline-download")
                if downloads.busy {
                    ProgressView(value: downloads.progress)
                    Button("取消下载") { downloads.cancel() }.accessibilityIdentifier("offline-cancel")
                }
                if let error = downloads.error { Text(error).font(.caption).foregroundStyle(.red).accessibilityIdentifier("offline-error") }
                Text(storageUsage)
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("offline-storage-usage")
                ForEach(downloads.entries) { entry in
                    VStack(alignment: .leading) {
                        Button("离线播放：" + entry.name) {
                            guard let file = downloads.fileURL(entry) else { return }
                            library.playLocalFile(file, name: entry.name)
                        }.accessibilityIdentifier("offline-play-" + entry.name)
                        HStack {
                            Text(ByteCountFormatter.string(fromByteCount: entry.bytes, countStyle: .file)).font(.caption)
                            Button("删除：" + entry.name, role: .destructive) {
                                pendingDeletion = entry
                            }.accessibilityIdentifier("offline-delete-" + entry.name)
                        }
                    }
                }
                Text("最多 20 个文件，总计 2 GiB，单文件 512 MiB。当前支持 MP4/M4V/MOV/MP3/M4A/AAC；不保存直播、HLS、DRM 或需要请求头的媒体。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .alert("删除离线媒体？", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        ), presenting: pendingDeletion) { entry in
            Button("删除离线文件", role: .destructive) {
                // SwiftUI may clear isPresented before invoking the action.
                // Use the entry captured at presentation, not mutable alert state.
                if let file = downloads.fileURL(entry) { library.stopLocalFile(file) }
                downloads.remove(entry)
                pendingDeletion = nil
            }
            Button("取消", role: .cancel) { pendingDeletion = nil }
        } message: { _ in
            Text("删除后无法恢复。取消不会影响已下载文件或正在播放的媒体。")
        }
    }
}
