import Combine
import Foundation

@MainActor
final class NativeOfflineDownloads: ObservableObject {
    @Published private(set) var entries: [NativeOfflineMediaEntry] = []
    @Published private(set) var busy = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var error: String?
    private var catalog: NativeOfflineMediaCatalog?
    private var task: Task<Void, Never>?
    private var generation = UUID()

    init(directory: URL? = nil) {
        do {
            let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("TVNextOffline", isDirectory: true)
            catalog = try NativeOfflineMediaCatalog(directory: root)
            entries = catalog?.entries ?? []
        } catch { self.error = NativeOfflineError.storage.localizedDescription }
    }

    func start(address: String, name: String) {
        guard !busy, let catalog else { return }
        error = nil
        guard let url = NativeOfflineMediaCatalog.sourceURL(address) else {
            error = NativeOfflineError.unsupported.localizedDescription; return
        }
        guard entries.count < catalog.maxEntries, catalog.availableBytes > 0 else {
            error = NativeOfflineError.quota.localizedDescription; return
        }
        let id = UUID()
        generation = id
        let staging = catalog.stagingURL(id)
        let maxBytes = catalog.availableBytes
        busy = true
        progress = 0
        task = Task { @MainActor [weak self] in
            do {
                try await NativeOfflineTransfer.download(url, to: staging, maxBytes: maxBytes) { value in
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == id, self.busy else { return }
                        self.progress = value
                    }
                }
                guard let self, self.generation == id, !Task.isCancelled else {
                    try? FileManager.default.removeItem(at: staging); return
                }
                _ = try catalog.commit(id: id, name: name, fileExtension: url.pathExtension.lowercased())
                self.entries = catalog.entries
            } catch {
                try? FileManager.default.removeItem(at: staging)
                if let self, self.generation == id, !Task.isCancelled {
                    // URLError descriptions can contain signed URLs. Show fixed text only.
                    self.error = (error as? NativeOfflineError)?.localizedDescription ?? "下载中断，请检查网络后重新下载。"
                }
            }
            if let self, self.generation == id { self.busy = false; self.task = nil }
        }
    }

    func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        busy = false
        progress = 0
    }

    func fileURL(_ entry: NativeOfflineMediaEntry) -> URL? { catalog?.fileURL(entry) }

    func remove(_ entry: NativeOfflineMediaEntry) {
        do { try catalog?.remove(entry); entries = catalog?.entries ?? []; error = nil }
        catch { self.error = NativeOfflineError.storage.localizedDescription }
    }
}
