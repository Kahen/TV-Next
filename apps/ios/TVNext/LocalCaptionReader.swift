import Foundation

/// Reads a user-selected SRT/VTT/ASS/SSA document from Files, including an
/// SMB-backed File Provider. The provider is accessed only while the explicit
/// import is active; its URL, credentials and contents are never persisted.
enum LocalCaptionReader {
    static let maxBytes = 1_048_576
    private static let chunkBytes = 65_536
    private static let supportedExtensions: Set<String> = ["srt", "vtt", "ass", "ssa"]

    /// The system picker can report a user dismissal as a Cocoa error.
    /// A File Provider failure is not equivalent to a user cancellation.
    static func isUserCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let ns = error as NSError
        return ns.domain == NSCocoaErrorDomain && ns.code == CocoaError.userCancelled.rawValue
    }

    static func load(_ source: URL, encoding: CaptionTextEncoding = .unicode) async throws -> [CaptionCue] {
        try Task<Never, Never>.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try readAndParse(source, encoding: encoding)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func readAndParse(_ source: URL, encoding: CaptionTextEncoding) throws -> [CaptionCue] {
        guard source.isFileURL, supportedExtensions.contains(source.pathExtension.lowercased()) else {
            throw CaptionError.invalidTimeline
        }
        try Task<Never, Never>.checkCancellation()
        #if canImport(Darwin)
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        // File Providers can expose placeholders until a coordinated read
        // hydrates them. Keep this blocking operation off the SwiftUI actor.
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<[CaptionCue], Error>?
        coordinator.coordinate(readingItemAt: source, options: [], error: &coordinationError) { url in
            result = Result { try readBounded(url, encoding: encoding) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CaptionError.unavailableFile }
        return try result.get()
        #else
        return try readBounded(source, encoding: encoding)
        #endif
    }

    private static func readBounded(_ url: URL, encoding: CaptionTextEncoding) throws -> [CaptionCue] {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attributes[.type] as? FileAttributeType) == .typeRegular else {
            throw CaptionError.invalidTimeline
        }
        if let declared = (attributes[.size] as? NSNumber)?.int64Value,
           declared > Int64(maxBytes) {
            throw CaptionError.tooLarge
        }
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var data = Data()
        while true {
            try Task<Never, Never>.checkCancellation()
            // Read one extra byte when exactly at the cap: declared provider
            // sizes can be missing, stale or deliberately inaccurate.
            let remaining = maxBytes + 1 - data.count
            let chunk = try input.read(upToCount: min(chunkBytes, remaining)) ?? Data()
            if chunk.isEmpty { break }
            guard chunk.count <= maxBytes - data.count else {
                throw CaptionError.tooLarge
            }
            data.append(chunk)
        }
        try Task<Never, Never>.checkCancellation()
        return try CaptionParser.parse(data, encoding: encoding)
    }
}
