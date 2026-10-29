import Combine
import Foundation

/// Keeps a late or cancelled subscription subtitle response from replacing a
/// newer choice or the captions for another installed AVPlayerItem.
@MainActor
final class NativeRemoteCaptionLoader: ObservableObject {
    typealias Fetch = @MainActor (TVNextAPI, String) async throws -> String
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    private let fetch: Fetch
    private var request = UUID()
    private var task: Task<Void, Never>?

    init(fetch: @escaping Fetch = { api, url in
        let response: NativeTextResponse = try await api.request("resources/text", body: NativeResourceRequest(url: url))
        return response.content
    }) { self.fetch = fetch }

    @discardableResult
    func load(_ source: NativePlaybackResource, api: TVNextAPI,
              isCurrent: @escaping @MainActor () -> Bool,
              apply: @escaping @MainActor ([CaptionCue], String) -> Void) -> Task<Void, Never> {
        cancel()
        let id = request
        busy = true
        let fetch = self.fetch
        let pending = Task { @MainActor [weak self] in
            defer {
                if let self, self.request == id { self.busy = false; self.task = nil }
            }
            do {
                let text = try await fetch(api, source.url)
                guard let self, !Task.isCancelled, self.request == id, isCurrent() else { return }
                let cues = try CaptionParser.parse(Data(text.utf8))
                apply(cues, source.name)
            } catch {
                if let self, !Task.isCancelled, self.request == id, isCurrent() {
                    self.error = (error as? CaptionError)?.localizedDescription ?? "字幕加载失败，请重试或选择其他字幕。"
                }
            }
        }
        task = pending
        return pending
    }

    func cancel() {
        request = UUID()
        task?.cancel()
        task = nil
        busy = false
        error = nil
    }
}
