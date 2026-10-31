import Foundation

@main struct SMBFilesSmoke {
    static func main() async throws {
        let fm = FileManager.default
        let source = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        let bytes = Data(repeating: 0xAB, count: 2_500_000)
        try bytes.write(to: source)
        defer { try? fm.removeItem(at: source) }
        let staged = try await LocalMediaStager.stage(source)
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
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await LocalMediaStager.stage(source)
        }
        do { _ = try await cancelled.value; fatalError("cancelled accepted") }
        catch is CancellationError {}
        print("Files SMB staging: positive, empty, oversized, unsupported, cancelled passed")
    }
}
