import AVFoundation
import SwiftUI

struct NativePlaybackDiagnosticsView: View {
    @ObservedObject var library: MediaLibraryStore
    @State private var expanded = false
    @State private var metadata: NativeMediaMetadata?
    @State private var timeline: NativePlaybackTimeline?
    @State private var loading = false
    @State private var unavailable = false
    @State private var request = UUID()
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private struct Selection: Equatable {
        let item: ObjectIdentifier?
        let expanded: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Keep the identifier on the actual full-width action, rather than
            // the container: SwiftUI can propagate container identifiers to
            // descendants and hide their independent accessibility identities.
            Button {
                expanded.toggle()
                if expanded { timeline = NativePlaybackTimeline.capture(library.player) }
            } label: {
                Label("播放诊断", systemImage: expanded ? "chevron.down" : "chevron.right")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("playback-diagnostics")
            .accessibilityValue(expanded ? "已展开" : "已收起")
            if expanded {
            VStack(alignment: .leading, spacing: 6) {
                Text("引擎：AVPlayer").font(.caption)
                if let timeline {
                    Text("状态：" + timeline.state).accessibilityIdentifier("diagnostics-state")
                    Text("进度：" + timeline.position + " / " + timeline.duration)
                    Text("前方缓冲：" + timeline.buffered)
                    if let error = timeline.error { Text("错误码：" + error).foregroundStyle(.red) }
                }
                if let metadata {
                    ForEach(metadata.video, id: \.self) { Text("视频：" + $0) }
                    ForEach(metadata.audio, id: \.self) { Text("音频：" + $0) }
                    if metadata.video.isEmpty && metadata.audio.isEmpty { Text("媒体未报告编码信息。") }
                }
                if loading { ProgressView("读取媒体元数据…") }
                if unavailable { Text("暂时无法读取编码信息，可在媒体准备后刷新。") }
                Button("刷新播放诊断") { Task { await refresh() } }
                    .accessibilityIdentifier("diagnostics-refresh")
                Text("编码来自媒体格式描述；系统未公开实际硬件解码器选择。诊断不保存或显示媒体 URL、请求头及原始错误日志。")
                    .font(.caption2).foregroundStyle(.secondary)
            }.font(.caption).padding(.top, 8)
            }
        }
        .task(id: Selection(item: library.player.currentItem.map(ObjectIdentifier.init), expanded: expanded)) {
            if expanded { await refresh() }
            else { request = UUID(); loading = false; metadata = nil; timeline = nil }
        }
        .onReceive(timer) { _ in
            if expanded { timeline = NativePlaybackTimeline.capture(library.player) }
        }
        .onDisappear { request = UUID(); loading = false }
    }

    @MainActor
    private func refresh() async {
        let id = UUID()
        request = id
        timeline = NativePlaybackTimeline.capture(library.player)
        metadata = nil
        unavailable = false
        guard let item = library.player.currentItem else { loading = false; return }
        loading = true
        defer { if request == id { loading = false } }
        do {
            let value = try await NativeMediaMetadata.collect(item.asset)
            guard !Task.isCancelled, request == id, expanded, library.player.currentItem === item else { return }
            metadata = value
            timeline = NativePlaybackTimeline.capture(library.player)
        } catch {
            if !Task.isCancelled, request == id, expanded, library.player.currentItem === item { unavailable = true }
        }
    }
}
