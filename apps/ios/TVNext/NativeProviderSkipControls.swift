import SwiftUI

struct NativeProviderSkipControls: View {
    @ObservedObject var library: MediaLibraryStore
    @State private var feedback: String?

    var body: some View {
        Group {
            if !library.providerSkipSegments.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("来源片段标记：\(library.providerSkipSegments.count) 个")
                        .font(.subheadline)
                        .accessibilityIdentifier("provider-skip-count")
                    TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                        let segment = library.activeProviderSkipSegment
                        let generation = library.playbackGeneration
                        Button(segment?.label ?? "当前不在来源标记片段内") {
                            guard let segment else { return }
                            feedback = library.skipProviderSegment(segment, generation: generation)
                                ? "已跳过来源标记片段。" : "播放位置已变化，或当前媒体不支持定位。"
                        }
                        .buttonStyle(.bordered)
                        .disabled(segment == nil)
                        .accessibilityIdentifier("skip-provider-segment")
                    }
                    Text("进入标记范围后可手动跳过；来源标记仅用于本次播放。")
                        .font(.caption).foregroundStyle(.secondary)
                    if let feedback {
                        Text(feedback).font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("provider-skip-feedback")
                    }
                }
            }
        }
        .onChange(of: library.playbackGeneration) { _, _ in feedback = nil }
    }
}
