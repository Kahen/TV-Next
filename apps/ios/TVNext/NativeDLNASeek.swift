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

    /// Parse only canonical ASCII HH:MM:SS before any network request.
    static func parseAbsolute(_ text: String) throws -> Int {
        guard text.utf8.count == 8 else { throw NativeDLNAError.invalidSeek }
        let bytes = Array(text.utf8)
        guard bytes[2] == 58, bytes[5] == 58 else {
            throw NativeDLNAError.invalidSeek
        }
        for index in [0, 1, 3, 4, 6, 7] {
            guard (48...57).contains(bytes[index]) else { throw NativeDLNAError.invalidSeek }
        }
        let hours = Int(bytes[0] - 48) * 10 + Int(bytes[1] - 48)
        let minutes = Int(bytes[3] - 48) * 10 + Int(bytes[4] - 48)
        let seconds = Int(bytes[6] - 48) * 10 + Int(bytes[7] - 48)
        guard minutes < 60, seconds < 60 else { throw NativeDLNAError.invalidSeek }
        return hours * 3600 + minutes * 60 + seconds
    }

    static func absoluteTarget(position: NativeDLNAPosition, requestedSeconds: Int) throws -> Int {
        guard let duration = position.durationSeconds, duration > 0,
              duration <= maxSeconds, position.seconds >= 0,
              position.seconds <= duration else { throw NativeDLNAError.unsupportedSeek }
        guard (0...duration).contains(requestedSeconds) else { throw NativeDLNAError.invalidSeek }
        return requestedSeconds
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
    /// Non-atomic fresh-state, fresh-position, then explicit REL_TIME Seek.
    /// A SOAP acknowledgement is not proof of completed playback.
    static func seekAbsolute(endpoint: URL, targetText: String) async throws -> Int {
        let requested = try NativeDLNASeek.parseAbsolute(targetText)
        let approved = try rendererURL(endpoint.absoluteString)
        let state = try await queryState(endpoint: approved)
        guard state == .playing || state == .pausedPlayback else {
            throw NativeDLNAError.unsupportedSeek
        }
        try Task.checkCancellation()
        let position = try await queryPosition(endpoint: approved)
        let target = try NativeDLNASeek.absoluteTarget(position: position, requestedSeconds: requested)
        try Task.checkCancellation()
        try await send(.seek, endpoint: approved, seekSeconds: target)
        return target
    }

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
