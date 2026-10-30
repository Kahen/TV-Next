import Foundation

/// A deliberately small AVTransport REL_TIME seek subset. No automatic polling,
/// renderer discovery, cached position, or background media control.
enum NativeDLNASeek {
    static let stepSeconds = 15
    static let maxSeconds = 99 * 3600 + 59 * 60 + 59

    static func target(_ seconds: Int) throws -> String {
        guard (0...maxSeconds).contains(seconds) else { throw NativeDLNAError.invalidSeek }
        return String(format: "%02d:%02d:%02d", seconds / 3600,
                      seconds / 60 % 60, seconds % 60)
    }

    static func relativeTarget(position: NativeDLNAPosition, deltaSeconds: Int) throws -> Int {
        guard deltaSeconds == -stepSeconds || deltaSeconds == stepSeconds else {
            throw NativeDLNAError.invalidSeek
        }
        guard let duration = position.durationSeconds, duration > 0,
              duration <= maxSeconds, position.seconds >= 0,
              position.seconds <= duration else { throw NativeDLNAError.unsupportedSeek }
        // Duration is bounded, so adding +/-15 cannot overflow Int.
        return min(duration, max(0, position.seconds + deltaSeconds))
    }
}

extension NativeDLNA {
    /// Fresh device state and position are required before each explicit Seek.
    /// A renderer can change state between requests; the final SOAP response
    /// is only a command acknowledgement, not proof of completed playback.
    static func seekRelative(endpoint: URL, deltaSeconds: Int) async throws -> Int {
        guard deltaSeconds == -NativeDLNASeek.stepSeconds ||
              deltaSeconds == NativeDLNASeek.stepSeconds else {
            throw NativeDLNAError.invalidSeek
        }
        let approved = try rendererURL(endpoint.absoluteString)
        let state = try await queryState(endpoint: approved)
        guard state == .playing || state == .pausedPlayback else {
            throw NativeDLNAError.unsupportedSeek
        }
        try Task.checkCancellation()
        let position = try await queryPosition(endpoint: approved)
        let target = try NativeDLNASeek.relativeTarget(position: position, deltaSeconds: deltaSeconds)
        try Task.checkCancellation()
        try await send(.seek, endpoint: approved, seekSeconds: target)
        return target
    }
}
