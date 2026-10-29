import SwiftUI

/// User-created boundaries, with explicit opt-in automatic playback skipping.
struct NativeIntroOutroControls: View {
    @ObservedObject var library: MediaLibraryStore
    @State private var feedback: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("手动片头 / 片尾标记").font(.subheadline).fontWeight(.medium)
            Text("在片头结束或片尾开始的位置手动标记；可按需跳过，或为这部影片开启自动跳过。手动拖回已跳过的部分不会反复跳转。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("标记片头结束") { act(library.markIntroEnd(), error: "只能在长于 2 分钟的视频前半段标记片头结束。") }
                    .accessibilityIdentifier("mark-intro-end")
                Button("标记片尾开始") { act(library.markOutroStart(), error: "只能在长于 2 分钟的视频后半段标记片尾开始。") }
                    .accessibilityIdentifier("mark-outro-start")
            }
            .buttonStyle(.bordered)
            .disabled(library.player.currentItem == nil)
            if let markers = library.introOutroMarkers {
                Toggle("自动跳过这部影片的标记片段", isOn: Binding(
                    get: { library.introOutroMarkers?.automatic == true },
                    set: { library.setAutomaticSkipEnabled($0) }
                )).accessibilityIdentifier("automatic-intro-outro")
                HStack {
                    Button("跳过片头") { act(library.skipMarkedIntro(), error: "当前播放位置已经超过片头，或媒体不支持定位。") }
                        .accessibilityIdentifier("skip-marked-intro")
                        .disabled(markers.introEnd == nil)
                    Button("跳过片尾") { act(library.skipMarkedOutro(), error: "只有播放进入已标记片尾时才可跳过。") }
                        .accessibilityIdentifier("skip-marked-outro")
                        .disabled(markers.outroStart == nil)
                    Button("清除标记") { library.clearIntroOutroMarkers(); feedback = nil }
                        .accessibilityIdentifier("clear-intro-outro")
                }
                .buttonStyle(.bordered)
                if let intro = markers.introEnd {
                    Text("片头结束：\(Int(intro)) 秒").font(.caption).foregroundStyle(.secondary)
                }
                if let outro = markers.outroStart {
                    Text("片尾开始：\(Int(outro)) 秒").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let feedback {
                Text(feedback).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("intro-outro-feedback")
            }
        }
        .onChange(of: library.playbackGeneration) { _, _ in feedback = nil }
    }

    private func act(_ succeeded: Bool, error: String) {
        feedback = succeeded ? nil : error
    }
}
