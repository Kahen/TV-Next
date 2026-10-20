import SwiftUI
import AVKit

struct ContentView: View {
    @State private var serverURL = "http://localhost:8080"
    @State private var manualURL = ""
    @State private var playlistText = ""
    @State private var channels: [TVChannel] = []
    @State private var player: AVPlayer?
    @State private var currentTitle = "未选择媒体"
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            VideoPlayer(player: player)
                                .frame(minHeight: 215)
                                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                                .background(Color.black)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            Text(currentTitle).font(.headline)
                                .accessibilityLabel("正在播放：" + currentTitle)
                        }
                    }

                    GroupBox("快速播放") {
                        HStack {
                            TextField("https://example.org/movie.m3u8", text: $manualURL)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder)
                            Button("播放") { play(urlString: manualURL, title: "自定义 URL") }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(.top, 8)
                    }

                    GroupBox("M3U 播放列表") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("需要 TV-Next API。模拟器默认使用 localhost；真机请填写你自己服务器的地址。")
                                .font(.footnote).foregroundStyle(.secondary)
                            TextField("API 地址", text: $serverURL)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder)
                            TextEditor(text: $playlistText)
                                .font(.system(.footnote, design: .monospaced))
                                .frame(height: 125)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray.opacity(0.3)))
                            Button(isLoading ? "解析中…" : "解析播放列表") {
                                Task { await importPlaylist() }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isLoading)
                        }
                        .padding(.top, 8)
                    }

                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red).font(.footnote)
                    }

                    if !channels.isEmpty {
                        GroupBox("频道 · " + String(channels.count)) {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach(channels) { channel in
                                    Button {
                                        play(urlString: channel.url, title: channel.name)
                                    } label: {
                                        HStack {
                                            Image(systemName: "play.circle")
                                            VStack(alignment: .leading) {
                                                Text(channel.name).font(.subheadline).fontWeight(.semibold)
                                                Text(channel.group).font(.caption).foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right").font(.caption)
                                        }.padding(.vertical, 7)
                                    }
                                    .buttonStyle(.plain)
                                    Divider()
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                    Text("不内置任何媒体来源。播放格式及网络权限取决于 iOS 和内容提供方。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: 850)
                .frame(maxWidth: .infinity)
                .padding()
            }
            .navigationTitle("TV-Next")
            .onDisappear { player?.pause() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("PERSONAL MEDIA")
                .font(.caption2).tracking(3).foregroundStyle(.secondary)
            Text("你的媒体，随处播放。")
                .font(.largeTitle).fontWeight(.bold)
            Text("iPhone / iPad 原生播放器 · 初期预览")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func play(urlString: String, title: String) {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.user == nil, url.password == nil else {
            errorMessage = "请输入有效的 HTTP(S) 媒体地址。"
            return
        }
        errorMessage = nil
        player?.pause()
        player = AVPlayer(url: url)
        currentTitle = title
        player?.play()
    }

    @MainActor
    private func importPlaylist() async {
        guard let server = URL(string: serverURL) else {
            errorMessage = "服务器地址无效"
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            channels = try await TVNextAPI(server: server).parsePlaylist(playlistText)
            errorMessage = channels.isEmpty ? "没有可解析的 HTTP(S) 频道。" : nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ContentView()
}
