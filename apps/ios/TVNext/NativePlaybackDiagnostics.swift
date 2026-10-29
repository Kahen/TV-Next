import AVFoundation
import CoreMedia
import Foundation

struct NativeMediaMetadata: Equatable {
    let video: [String]
    let audio: [String]

    static func codec(_ value: FourCharCode) -> String {
        let bytes = [UInt8((value >> 24) & 255), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)]
        let raw = bytes.allSatisfy { (33...126).contains($0) } ? String(bytes: bytes, encoding: .ascii) : nil
        switch raw {
        case "avc1", "avc3": return "H.264 (\(raw!))"
        case "hvc1", "hev1": return "HEVC (\(raw!))"
        case "mp4a": return "AAC / MPEG-4 audio (mp4a)"
        case "ac-3": return "Dolby AC-3"
        case "ec-3": return "Dolby E-AC-3"
        default: return raw ?? String(format: "0x%08X", value)
        }
    }

    static func collect(_ asset: AVAsset) async throws -> NativeMediaMetadata {
        var video: [String] = [], audio: [String] = []
        for track in try await asset.load(.tracks).prefix(8) {
            try Task.checkCancellation()
            for format in try await track.load(.formatDescriptions).prefix(4) {
                let type = CMFormatDescriptionGetMediaType(format)
                let codec = codec(CMFormatDescriptionGetMediaSubType(format))
                if type == kCMMediaType_Video {
                    let size = CMVideoFormatDescriptionGetDimensions(format)
                    let dimensions = size.width > 0 && size.height > 0 ? " · \(size.width)×\(size.height)" : ""
                    let label = codec + dimensions
                    if !video.contains(label) { video.append(label) }
                } else if type == kCMMediaType_Audio {
                    var label = codec
                    if let stream = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
                        if stream.mSampleRate.isFinite, stream.mSampleRate > 0, stream.mSampleRate <= 768_000 {
                            label += " · \(Int(stream.mSampleRate)) Hz"
                        }
                        if stream.mChannelsPerFrame > 0, stream.mChannelsPerFrame <= 64 {
                            label += " · \(stream.mChannelsPerFrame) 声道"
                        }
                    }
                    if !audio.contains(label) { audio.append(label) }
                }
            }
        }
        return NativeMediaMetadata(video: Array(video.prefix(8)), audio: Array(audio.prefix(8)))
    }
}

struct NativePlaybackTimeline: Equatable {
    let state: String
    let position: String
    let duration: String
    let buffered: String
    let error: String?

    static func seconds(_ value: Double) -> String {
        value.isFinite && value >= 0 && value < 604_800 ? String(format: "%.1f 秒", value) : "未知 / 非有限时长"
    }

    /// AVFoundation/NSError userInfo and access/error logs can contain signed
    /// URLs, auth headers and server bodies. Only allowlisted domains + numeric
    /// codes are shown; no raw error description or log event is serialized.
    static func errorCode(_ error: Error?) -> String? {
        guard let error else { return nil }
        let value = error as NSError
        let allowed = ["AVFoundationErrorDomain", "NSURLErrorDomain", "NSOSStatusErrorDomain"]
        let domain = allowed.contains(value.domain) ? value.domain : "PlayerError"
        return domain + " (\(value.code))"
    }

    @MainActor
    static func capture(_ player: AVPlayer) -> NativePlaybackTimeline {
        guard let item = player.currentItem else {
            return NativePlaybackTimeline(state: "尚未选择媒体", position: "—", duration: "—", buffered: "—", error: nil)
        }
        let state: String
        if item.status == .failed { state = "播放失败" }
        else if item.status != .readyToPlay { state = "准备媒体" }
        else {
            switch player.timeControlStatus {
            case .playing: state = "播放中"
            case .waitingToPlayAtSpecifiedRate: state = "等待缓冲"
            default: state = "已暂停"
            }
        }
        let current = player.currentTime().seconds
        let ends = item.loadedTimeRanges.prefix(32).compactMap { value -> Double? in
            let range = value.timeRangeValue
            let start = range.start.seconds, end = CMTimeRangeGetEnd(range).seconds
            return current.isFinite && start.isFinite && end.isFinite && start <= current && end >= current ? end : nil
        }
        let lead = ends.max().map { min(86_400, max(0, $0 - current)) }
        return NativePlaybackTimeline(state: state, position: seconds(current), duration: seconds(item.duration.seconds),
            buffered: lead.map(seconds) ?? "未报告", error: errorCode(item.error))
    }
}
