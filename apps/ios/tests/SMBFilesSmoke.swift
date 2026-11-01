import Foundation

private final class CopyProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Int64] = []
    func append(_ value: Int64) {
        lock.lock()
        recorded.append(value)
        lock.unlock()
    }
    var values: [Int64] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
}

@main struct SMBFilesSmoke {
    static func main() async throws {
        let fm = FileManager.default
        let source = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        let bytes = Data(repeating: 0xAB, count: 2_500_000)
        try bytes.write(to: source)
        defer { try? fm.removeItem(at: source) }
        let progress = CopyProgressLog()
        let staged = try await LocalMediaStager.stage(source) { copied, total in
            precondition(total == Int64(bytes.count))
            progress.append(copied)
        }
        precondition(progress.values == [1_048_576, 2_097_152, Int64(bytes.count)])
        let copied = try Data(contentsOf: staged)
        precondition(copied == bytes)
        LocalMediaStager.discard(staged)
        precondition(!fm.fileExists(atPath: staged.path))

        let empty = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        _ = fm.createFile(atPath: empty.path, contents: Data())
        defer { try? fm.removeItem(at: empty) }
        do { _ = try await LocalMediaStager.stage(empty); fatalError("empty accepted") }
        catch LocalMediaError.emptyFile {}
        let handle = try FileHandle(forWritingTo: empty)
        try handle.truncate(atOffset: 2_147_483_649)
        try handle.close()
        do { _ = try await LocalMediaStager.stage(empty); fatalError("oversized accepted") }
        catch LocalMediaError.oversizedFile {}
        do { _ = try await LocalMediaStager.stage(source.deletingPathExtension().appendingPathExtension("mkv")); fatalError("unsupported accepted") }
        catch LocalMediaError.unsupportedFormat {}
        // Cancel from the worker's first chunk callback to deterministically
        // exercise cleanup of a partially written cache file.
        let cache = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TVNextImported", isDirectory: true)
        let before = Set((try? fm.contentsOfDirectory(atPath: cache.path)) ?? [])
        do {
            _ = try await LocalMediaStager.stage(source) { copied, _ in
                if copied >= 1_048_576 {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
            fatalError("mid-copy cancellation accepted")
        } catch is CancellationError {}
        precondition(Set((try? fm.contentsOfDirectory(atPath: cache.path)) ?? []) == before)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await LocalMediaStager.stage(source)
        }
        do { _ = try await cancelled.value; fatalError("cancelled accepted") }
        catch is CancellationError {}
        print("Files SMB staging: progress, positive, empty, oversized, unsupported, mid-copy/preflight cancellation and cleanup passed")
    }
}
