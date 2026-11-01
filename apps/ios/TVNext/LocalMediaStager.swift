import Foundation

enum LocalMediaError: LocalizedError, Equatable {
    case unsupportedFormat
    case emptyFile
    case oversizedFile
    case unavailableFile
    case insufficientStorage

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "只能选择 MP4、M4V、MOV、MP3、M4A 或 AAC；实际播放仍取决于设备编解码能力。"
        case .emptyFile: return "无法播放空文件。"
        case .oversizedFile: return "本地文件超过当前 2 GiB 导入上限。"
        case .unavailableFile: return "无法读取文件提供方中的媒体；请检查共享连接与文件权限。"
        case .insufficientStorage: return "设备可用存储空间不足，无法导入媒体；请释放本机空间后重试。"
        }
    }
}

/// Read-only import from a user-selected Files document, including Files' SMB provider.
/// A security-scoped, coordinated read is staged into an app-owned temporary cache.
/// No SMB credentials, provider URL, or remote media source is persisted.
enum LocalMediaStager {
    private static let extensions: Set<String> = ["mp4", "m4v", "mov", "mp3", "m4a", "aac"]
    static let maxBytes: Int64 = 2_147_483_648
    private static let chunkBytes = 1_048_576
    // Preserve headroom for iOS and other apps. This is a conservative
    // preflight, not a guarantee that the volume cannot fill during a copy.
    static let freeSpaceReserveBytes: Int64 = 64 * 1_048_576

    static func hasCapacity(availableBytes: Int64, expectedBytes: Int64?) -> Bool {
        guard availableBytes >= freeSpaceReserveBytes else { return false }
        guard let expectedBytes, expectedBytes > 0 else { return true }
        // Subtract first to avoid overflow on provider-supplied sizes.
        return expectedBytes <= availableBytes - freeSpaceReserveBytes
    }

    private static func preflightSpace(in cache: URL, expectedBytes: Int64?) throws {
        // Some Files providers cannot report a file size. A missing volume
        // capacity is not a reason to reject a potentially valid import;
        // actual writes still enforce the limit and clean up on failure.
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: cache.path),
              let free = (attributes[.systemFreeSize] as? NSNumber)?.int64Value else { return }
        guard hasCapacity(availableBytes: free, expectedBytes: expectedBytes) else {
            throw LocalMediaError.insufficientStorage
        }
    }

    static func normalizedWriteError(_ error: Error) -> Error {
        let ns = error as NSError
        if (ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError) ||
            (ns.domain == NSPOSIXErrorDomain && ns.code == 28) {
            return LocalMediaError.insufficientStorage
        }
        return error
    }

    private static func writeChunk(_ bytes: Data, to output: FileHandle) throws {
        do {
            try output.write(contentsOf: bytes)
        } catch {
            throw normalizedWriteError(error)
        }
    }

    static func stage(_ source: URL, onProgress: (@Sendable (Int64, Int64?) -> Void)? = nil) async throws -> URL {
        try Task<Never, Never>.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try copyFile(source, onProgress: onProgress)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func copyFile(_ source: URL, onProgress: (@Sendable (Int64, Int64?) -> Void)?) throws -> URL {
        guard source.isFileURL, extensions.contains(source.pathExtension.lowercased()) else {
            throw LocalMediaError.unsupportedFormat
        }
        try Task<Never, Never>.checkCancellation()

        #if canImport(Darwin)
        let permission = source.startAccessingSecurityScopedResource()
        defer { if permission { source.stopAccessingSecurityScopedResource() } }
        // A File Provider (including Files' SMB connection) can materialize a
        // placeholder only when accessed through a coordinated read.
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var staged: Result<URL, Error>?
        coordinator.coordinate(readingItemAt: source, options: [], error: &coordinationError) { coordinated in
            staged = Result { try streamCopy(coordinated, extension: source.pathExtension.lowercased(), onProgress: onProgress) }
        }
        if let coordinationError { throw coordinationError }
        guard let staged else { throw LocalMediaError.unavailableFile }
        return try staged.get()
        #else
        return try streamCopy(source, extension: source.pathExtension.lowercased(), onProgress: onProgress)
        #endif
    }

    private static func streamCopy(_ source: URL, extension ext: String, onProgress: (@Sendable (Int64, Int64?) -> Void)?) throws -> URL {
        let fileManager = FileManager.default
        let attrs = try fileManager.attributesOfItem(atPath: source.path)
        guard (attrs[.type] as? FileAttributeType) == .typeRegular else {
            throw LocalMediaError.unsupportedFormat
        }
        // Some File Providers cannot report a reliable size until hydrated.
        // Preflight known oversized files, then enforce the limit on every read.
        if let size = (attrs[.size] as? NSNumber)?.int64Value, size > maxBytes {
            throw LocalMediaError.oversizedFile
        }
        let cache = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TVNextImported", isDirectory: true)
        try fileManager.createDirectory(at: cache, withIntermediateDirectories: true)
        try preflightSpace(in: cache, expectedBytes: (attrs[.size] as? NSNumber)?.int64Value)
        try Task<Never, Never>.checkCancellation()
        let destination = cache.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        guard fileManager.createFile(atPath: destination.path, contents: nil) else {
            throw LocalMediaError.unavailableFile
        }
        var completed = false
        defer { if !completed { try? fileManager.removeItem(at: destination) } }
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        let expected = (attrs[.size] as? NSNumber)?.int64Value
        let knownTotal = expected.flatMap { $0 > 0 && $0 <= maxBytes ? $0 : nil }
        var total: Int64 = 0
        while true {
            try Task<Never, Never>.checkCancellation()
            let bytes = try input.read(upToCount: chunkBytes) ?? Data()
            if bytes.isEmpty { break }
            guard Int64(bytes.count) <= maxBytes - total else { throw LocalMediaError.oversizedFile }
            try writeChunk(bytes, to: output)
            total += Int64(bytes.count)
            // Only report bytes actually copied. File Provider sizes may be
            // absent or stale; never report a percentage above 100%.
            onProgress?(total, knownTotal.flatMap { total <= $0 ? $0 : nil })
        }
        guard total > 0 else { throw LocalMediaError.emptyFile }
        try Task<Never, Never>.checkCancellation()
        try output.synchronize()
        completed = true
        return destination
    }

    /// Cold-launch maintenance only. Staged Files documents are never restored
    /// across app restarts; a crash can otherwise strand a large private copy.
    /// Do not invoke this while an import or local playback is active.
    @discardableResult
    static func purgeAbandonedImports(in directory: URL? = nil) -> Int {
        let fm = FileManager.default
        let cache = directory ?? fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TVNextImported", isDirectory: true)
        // Never traverse a redirected cache root or delete arbitrary user files.
        guard let root = try? cache.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              root.isDirectory == true, root.isSymbolicLink != true,
              let entries = try? fm.contentsOfDirectory(
                at: cache, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
              ) else { return 0 }
        var removed = 0
        for entry in entries {
            guard extensions.contains(entry.pathExtension.lowercased()),
                  UUID(uuidString: entry.deletingPathExtension().lastPathComponent) != nil,
                  let kind = try? entry.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  kind.isRegularFile == true, kind.isSymbolicLink != true else { continue }
            if (try? fm.removeItem(at: entry)) != nil { removed += 1 }
        }
        return removed
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
