import SwiftUI

/// Explicit, accessible inline controls share the same bounded seek validation
/// as lock-screen and Control Center commands. They never seek live streams.
struct NativeSeekControls: View {
    @ObservedObject var library: MediaLibraryStore
    @State private var feedback: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Button("后退 15 秒", systemImage: "gobackward.15") { skip(-15) }
                    .accessibilityIdentifier("seek-back-15")
                Button("前进 15 秒", systemImage: "goforward.15") { skip(15) }
                    .accessibilityIdentifier("seek-forward-15")
            }
            .buttonStyle(.bordered)
            .disabled(library.player.currentItem == nil)
            if let feedback {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("seek-feedback")
            }
        }
        .onChange(of: library.playbackGeneration) { _, _ in feedback = nil }
    }

    private func skip(_ seconds: TimeInterval) {
        feedback = library.handleSystemPlaybackCommand(.skip(seconds))
            ? nil : "当前媒体尚未就绪，或不支持直播/未知时长定位。"
    }
}
