import Foundation

/// Validates a single read-only SMB file request before it reaches a transport.
/// The transport must still enforce authentication, cancellation and a total transfer quota.
struct NativeSMBReadRange: Equatable {
    let offset: Int64
    let length: Int
    static let maximumChunkBytes = 1024 * 1024

    init?(offset: Int64, length: Int, fileSize: Int64) {
        guard fileSize > 0, offset >= 0, offset < fileSize,
              length > 0, length <= Self.maximumChunkBytes,
              Int64(length) <= fileSize - offset else { return nil }
        self.offset = offset
        self.length = length
    }
}
