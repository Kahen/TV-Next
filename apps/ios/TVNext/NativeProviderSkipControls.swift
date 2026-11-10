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
                    Toggle("自动跳过本次播放的来源片段", isOn: Binding(
                        get: { library.automaticProviderSkipEnabled },
                        set: { enabled in
                            // Read the current generation when the user acts, not when SwiftUI renders.
                            _ = library.setAutomaticProviderSkipEnabled(enabled, generation: library.playbackGeneration)
                        }
                    ))
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("automatic-provider-skip")
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
                    let generation = library.playbackGeneration
                    Text("默认手动跳过。开启后仅在播放中自动跳过；拖回已跳过的片段可重看，换集或重试后需重新开启。")
                        .font(.caption).foregroundStyle(.secondary)
                    if library.automaticProviderSkipCount > 0 {
                        Text("已自动跳过 \(library.automaticProviderSkipCount) 个来源片段。")
                            .font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("automatic-provider-skip-feedback")
                    }
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
