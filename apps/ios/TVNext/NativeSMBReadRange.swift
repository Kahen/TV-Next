import Foundation

/// Validates a single read-only SMB file request before it reaches a transport.
/// The transport must still enforce authentication, cancellation and a total transfer quota.
enum NativeSMBReadRange: Equatable {
    case bytes(offset: Int64, length: Int)
    static let maximumChunkBytes = 1024 * 1024

    init?(offset: Int64, length: Int, fileSize: Int64) {
        guard fileSize > 0, offset >= 0, offset < fileSize,
              length > 0, length <= Self.maximumChunkBytes,
              Int64(length) <= fileSize - offset else { return nil }
        self = .bytes(offset: offset, length: length)
    }

    var offset: Int64 {
        if case .bytes(let offset, _) = self { return offset }
        return 0
    }

    var length: Int {
        if case .bytes(_, let length) = self { return length }
        return 0
    }
}
