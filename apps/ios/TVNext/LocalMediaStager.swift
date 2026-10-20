import Foundation

enum LocalMediaError: LocalizedError {
    case unsupportedFormat
    case emptyFile
    case oversizedFile

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "只能选择 MP4、M4V、MOV、MP3、M4A 或 AAC；实际播放仍取决于设备编解码能力。"
        case .emptyFile: return "无法播放空文件。"
        case .oversizedFile: return "本地文件超过当前 2 GiB 导入上限。"
        }
    }
}

/// Copies a user-selected, security-scoped Files document into the sandbox.
/// Playback does not rely on the short-lived document-picker security scope.
/// No remote upload or persistence in the media library occurs.
enum LocalMediaStager {
    private static let extensions: Set<String> = ["mp4", "m4v", "mov", "mp3", "m4a", "aac"]

    static func stage(_ source: URL) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            try copyFile(source)
        }.value
    }

    private static func copyFile(_ source: URL) throws -> URL {
        guard source.isFileURL, extensions.contains(source.pathExtension.lowercased()) else {
            throw LocalMediaError.unsupportedFormat
        }
        let permission = source.startAccessingSecurityScopedResource()
        defer { if permission { source.stopAccessingSecurityScopedResource() } }

        let fileManager = FileManager.default
        let attrs = try fileManager.attributesOfItem(atPath: source.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? -1
        guard size > 0 else { throw LocalMediaError.emptyFile }
        guard size <= 2_147_483_648 else { throw LocalMediaError.oversizedFile }

        let cache = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TVNextImported", isDirectory: true)
        try fileManager.createDirectory(at: cache, withIntermediateDirectories: true)
        let destination = cache.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(source.pathExtension.lowercased())
        do {
            try fileManager.copyItem(at: source, to: destination)
            return destination
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    static func discard(_ file: URL?) {
        guard let file, file.isFileURL else { return }
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TVNextImported", isDirectory: true)
        guard file.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else {
            return
        }
        try? FileManager.default.removeItem(at: file)
    }
}
