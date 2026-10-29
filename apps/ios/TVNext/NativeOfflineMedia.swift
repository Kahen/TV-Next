import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum NativeOfflineError: LocalizedError {
    case unsupported, quota, invalidResponse, storage
    var errorDescription: String? {
        switch self {
        case .unsupported: return "离线下载支持无额外请求头的 HTTP(S) MP4/M4V/MOV/MP3/M4A/AAC 直链。"
        case .quota: return "离线空间不足：最多 20 个文件、总计 2 GiB、单文件 512 MiB。"
        case .invalidResponse: return "下载失败：服务器响应、文件大小或媒体类型无效；不跟随重定向。"
        case .storage: return "离线文件无法保存，请检查设备可用空间。"
        }
    }
}

struct NativeOfflineMediaEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let fileExtension: String
    let bytes: Int64
    var filename: String { id.uuidString + "." + fileExtension }
}

private struct NativeOfflineSnapshot: Codable {
    let version: Int
    let entries: [NativeOfflineMediaEntry]
}

/// Only generated file identities and display names are persisted. Source URLs,
/// signed queries, HTTP headers, cookies and resume blobs never enter this file.
/// Caller serializes access (the production owner is on the main actor).
final class NativeOfflineMediaCatalog {
    static let extensions: Set<String> = ["mp4", "m4v", "mov", "mp3", "m4a", "aac"]
    let directory: URL
    let maxFileBytes: Int64
    let maxTotalBytes: Int64
    let maxEntries: Int
    private(set) var entries: [NativeOfflineMediaEntry] = []
    private var manifest: URL { directory.appendingPathComponent("catalog.json") }
    var usedBytes: Int64 { entries.reduce(0) { $0 + $1.bytes } }
    var availableBytes: Int64 { min(maxFileBytes, max(0, maxTotalBytes - usedBytes)) }

    init(directory: URL, maxFileBytes: Int64 = 536_870_912,
         maxTotalBytes: Int64 = 2_147_483_648, maxEntries: Int = 20) throws {
        self.directory = directory.standardizedFileURL
        self.maxFileBytes = maxFileBytes
        self.maxTotalBytes = maxTotalBytes
        self.maxEntries = maxEntries
        let fm = FileManager.default
        try fm.createDirectory(at: self.directory, withIntermediateDirectories: true)
        // Offline copies are reproducible media, not device backup material.
        var resource = self.directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try resource.setResourceValues(values)
        if let size = try? fm.attributesOfItem(atPath: manifest.path)[.size] as? NSNumber,
           size.intValue <= 65_536,
           let data = try? Data(contentsOf: manifest),
           let saved = try? JSONDecoder().decode(NativeOfflineSnapshot.self, from: data),
           saved.version == 1 {
            var ids = Set<UUID>()
            for entry in saved.entries.prefix(maxEntries) {
                guard Self.extensions.contains(entry.fileExtension),
                      !entry.name.isEmpty, entry.name.count <= 180,
                      entry.bytes > 0, entry.bytes <= maxFileBytes,
                      entry.bytes <= maxTotalBytes - usedBytes,
                      ids.insert(entry.id).inserted,
                      Self.fileSize(self.directory.appendingPathComponent(entry.filename)) == entry.bytes else { continue }
                entries.append(entry)
            }
        }
        // A terminated transfer or failed atomic manifest write may leave files.
        // Cleanup is confined to this app-owned directory, never an imported URL.
        let retained = Set(entries.map(\.filename) + ["catalog.json"])
        for file in try fm.contentsOfDirectory(at: self.directory, includingPropertiesForKeys: nil) {
            if !retained.contains(file.lastPathComponent) { try? fm.removeItem(at: file) }
        }
    }

    static func sourceURL(_ raw: String) -> URL? {
        guard raw.utf8.count <= 4096, raw == raw.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || $0.value == 92 }),
              let parts = URLComponents(string: raw),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.fragment == nil,
              let url = parts.url, extensions.contains(url.pathExtension.lowercased()) else { return nil }
        return url
    }

    private static func fileSize(_ url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize else { return nil }
        return Int64(size)
    }

    func stagingURL(_ id: UUID) -> URL { directory.appendingPathComponent("partial-" + id.uuidString) }

    func fileURL(_ entry: NativeOfflineMediaEntry) -> URL? {
        guard entries.contains(entry) else { return nil }
        let file = directory.appendingPathComponent(entry.filename)
        return Self.fileSize(file) == entry.bytes ? file : nil
    }

    func commit(id: UUID, name: String, fileExtension: String) throws -> NativeOfflineMediaEntry {
        guard entries.count < maxEntries, !entries.contains(where: { $0.id == id }),
              Self.extensions.contains(fileExtension),
              let size = Self.fileSize(stagingURL(id)), size > 0,
              size <= availableBytes else { throw NativeOfflineError.quota }
        let title = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(180))
        let entry = NativeOfflineMediaEntry(id: id, name: title.isEmpty ? "离线媒体" : title,
                                           fileExtension: fileExtension, bytes: size)
        let target = directory.appendingPathComponent(entry.filename)
        try FileManager.default.moveItem(at: stagingURL(id), to: target)
        do { try write(entries + [entry]) }
        catch { try? FileManager.default.removeItem(at: target); throw NativeOfflineError.storage }
        entries.append(entry)
        return entry
    }

    func remove(_ entry: NativeOfflineMediaEntry) throws {
        guard entries.contains(entry) else { return }
        let updated = entries.filter { $0.id != entry.id }
        // Commit metadata first; a failed delete is cleaned on next launch.
        try write(updated)
        entries = updated
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(entry.filename))
    }

    private func write(_ entries: [NativeOfflineMediaEntry]) throws {
        let data = try JSONEncoder().encode(NativeOfflineSnapshot(version: 1, entries: entries))
        guard data.count <= 65_536 else { throw NativeOfflineError.storage }
        try data.write(to: manifest, options: .atomic)
    }
}

/// Streams into URLSession's temporary file. No full media allocation; every
/// progress callback and the final on-disk size enforce the caller's quota.
/// Redirects are deliberately refused, including same-origin redirects.
final class NativeOfflineTransfer: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let maxBytes: Int64
    private let progress: @Sendable (Double) -> Void
    private let fileExtension: String
    private var continuation: CheckedContinuation<Void, Error>?
    private let completionLock = NSLock()
    private var terminalResult: Result<Void, Error>?
    private var failure: Error?
    private var saved = false

    private init(destination: URL, maxBytes: Int64, fileExtension: String, progress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.maxBytes = maxBytes
        self.progress = progress
        self.fileExtension = fileExtension
    }

    static func download(_ url: URL, to destination: URL, maxBytes: Int64,
                         progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        try Task.checkCancellation()
        guard maxBytes > 0, NativeOfflineMediaCatalog.sourceURL(url.absoluteString) != nil else { throw NativeOfflineError.unsupported }
        let transfer = NativeOfflineTransfer(destination: destination, maxBytes: maxBytes,
                                             fileExtension: url.pathExtension.lowercased(), progress: progress)
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 1800
        let session = URLSession(configuration: config, delegate: transfer, delegateQueue: nil)
        var request = URLRequest(url: url)
        request.allowsCellularAccess = false
        let task = session.downloadTask(with: request) // Created before cancellation may invalidate the session.
        defer { session.invalidateAndCancel() }
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (pending: CheckedContinuation<Void, Error>) in
                    transfer.install(pending)
                    task.resume()
                }
            } onCancel: { task.cancel() }
            try Task.checkCancellation()
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    // A pre-cancelled parent can cancel the suspended URLSessionTask before
    // the continuation is installed. Retain its terminal result in either
    // callback ordering instead of losing the completion and hanging forever.
    private func install(_ pending: CheckedContinuation<Void, Error>) {
        completionLock.lock()
        let result = terminalResult
        if result == nil { continuation = pending }
        completionLock.unlock()
        if let result { pending.resume(with: result) }
    }

    private func finish(_ result: Result<Void, Error>) {
        completionLock.lock()
        guard terminalResult == nil else { completionLock.unlock(); return }
        terminalResult = result
        let pending = continuation
        continuation = nil
        completionLock.unlock()
        pending?.resume(with: result)
    }

    /// Reject text/playlist/error pages disguised as a downloadable media file.
    /// Codec decoding remains AVFoundation's responsibility.
    static func validHeader(_ header: Data, fileExtension: String) -> Bool {
        let bytes = Array(header)
        if ["mp4", "m4v", "m4a", "mov"].contains(fileExtension), bytes.count >= 12 {
            let atom = String(bytes: bytes[4..<8], encoding: .ascii)
            return atom == "ftyp" || fileExtension == "mov" && ["moov", "mdat", "wide", "free"].contains(atom ?? "")
        }
        guard bytes.count >= 3 else { return false }
        if fileExtension == "mp3" {
            return bytes.starts(with: [0x49, 0x44, 0x33]) || bytes[0] == 0xff && bytes[1] & 0xe0 == 0xe0
        }
        return fileExtension == "aac" && bytes[0] == 0xff && bytes[1] & 0xf6 == 0xf0
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > maxBytes || totalBytesExpectedToWrite > maxBytes {
            failure = NativeOfflineError.quota
            downloadTask.cancel()
        } else if totalBytesExpectedToWrite > 0 {
            progress(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard failure == nil else { return }
        guard let response = downloadTask.response as? HTTPURLResponse, response.statusCode == 200,
              response.expectedContentLength <= maxBytes,
              let attrs = try? FileManager.default.attributesOfItem(atPath: location.path),
              let size = (attrs[.size] as? NSNumber)?.int64Value, size > 0, size <= maxBytes,
              response.expectedContentLength < 0 || response.expectedContentLength == size else {
            failure = NativeOfflineError.invalidResponse
            return
        }
        let mime = response.mimeType?.lowercased() ?? "application/octet-stream"
        guard mime.hasPrefix("video/") || mime.hasPrefix("audio/") || mime == "application/octet-stream" else {
            failure = NativeOfflineError.invalidResponse
            return
        }
        do {
            let handle = try FileHandle(forReadingFrom: location)
            defer { try? handle.close() }
            let header = try handle.read(upToCount: 64) ?? Data()
            guard Self.validHeader(header, fileExtension: fileExtension) else {
                failure = NativeOfflineError.invalidResponse; return
            }
            try FileManager.default.moveItem(at: location, to: destination)
            saved = true
        }
        catch { failure = NativeOfflineError.storage }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        failure = NativeOfflineError.invalidResponse
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let problem = failure ?? error ?? (saved ? nil : NativeOfflineError.invalidResponse)
        if let problem {
            try? FileManager.default.removeItem(at: destination)
            finish(.failure(problem))
        } else { finish(.success(())) }
    }
}
