import Foundation
import MediaPlayer

enum NativePlaybackCommand {
    case play, pause, toggle, seek(TimeInterval), skip(TimeInterval), rate(Float)
}

struct NativeNowPlayingSnapshot {
    let title: String
    let elapsed: TimeInterval
    let duration: TimeInterval
    let rate: Float
    let defaultRate: Float

    var seekable: Bool { duration.isFinite && duration > 0 && duration < 604_800 }
    var info: [String: Any] {
        let bounded = String(title.filter { !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }.prefix(160))
        let safeTitle = bounded.isEmpty || bounded.contains("://") ? "TV-Next 媒体" : bounded
        var value: [String: Any] = [MPMediaItemPropertyTitle: safeTitle,
            MPNowPlayingInfoPropertyIsLiveStream: !seekable,
            MPNowPlayingInfoPropertyPlaybackRate: rate.isFinite ? rate : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: defaultRate.isFinite ? defaultRate : 1]
        if elapsed.isFinite && elapsed >= 0 {
            value[MPNowPlayingInfoPropertyElapsedPlaybackTime] = seekable ? min(elapsed,duration) : elapsed
        }
        if seekable { value[MPMediaItemPropertyPlaybackDuration] = duration }
        return value
    }
}

/// Own only this app's active player's targets. Old stores cannot overwrite the
/// new owner's metadata, and system callbacks synchronously validate on main.
@MainActor
final class NativeMediaControls {
    private static weak var owner: NativeMediaControls?
    private weak var library: MediaLibraryStore?
    private var targets: [(MPRemoteCommand, Any)] = []
    private let center = MPRemoteCommandCenter.shared()

    func activate(_ library: MediaLibraryStore) {
        if Self.owner !== self {
            Self.owner?.invalidate()
            Self.owner = self
        }
        self.library = library
        guard targets.isEmpty else { return }
        register(center.playCommand) { _ in .play }
        register(center.pauseCommand) { _ in .pause }
        register(center.stopCommand) { _ in .pause }
        register(center.togglePlayPauseCommand) { _ in .toggle }
        register(center.changePlaybackPositionCommand) { event in
            (event as? MPChangePlaybackPositionCommandEvent).map { .seek($0.positionTime) }
        }
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.preferredIntervals = [15]
        register(center.skipForwardCommand) { _ in .skip(15) }
        register(center.skipBackwardCommand) { _ in .skip(-15) }
        center.changePlaybackRateCommand.supportedPlaybackRates = [0.75,1,1.25,1.5,2]
        register(center.changePlaybackRateCommand) { event in
            (event as? MPChangePlaybackRateCommandEvent).map { .rate($0.playbackRate) }
        }
    }

    private func register(_ command: MPRemoteCommand, map: @escaping (MPRemoteCommandEvent) -> NativePlaybackCommand?) {
        let target = command.addTarget { [weak self] event in
            guard let action = map(event) else { return .commandFailed }
            return Self.onMain {
                guard let self, Self.owner === self, let library = self.library else { return .noSuchContent }
                return library.handleSystemPlaybackCommand(action) ? .success : .commandFailed
            }
        }
        targets.append((command,target))
    }

    nonisolated private static func onMain(_ work: @MainActor () -> MPRemoteCommandHandlerStatus) -> MPRemoteCommandHandlerStatus {
        if Thread.isMainThread { return MainActor.assumeIsolated { work() } }
        return DispatchQueue.main.sync { MainActor.assumeIsolated { work() } }
    }

    func publish(_ snapshot: NativeNowPlayingSnapshot?) {
        guard Self.owner === self else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = snapshot?.info
        let available = snapshot != nil
        center.playCommand.isEnabled = available
        center.pauseCommand.isEnabled = available
        center.stopCommand.isEnabled = available
        center.togglePlayPauseCommand.isEnabled = available
        center.changePlaybackPositionCommand.isEnabled = snapshot?.seekable == true
        center.skipForwardCommand.isEnabled = snapshot?.seekable == true
        center.skipBackwardCommand.isEnabled = snapshot?.seekable == true
        center.changePlaybackRateCommand.isEnabled = snapshot?.seekable == true
    }

    func invalidate() {
        if Self.owner === self {
            publish(nil)
            Self.owner = nil
        }
        for (command,target) in targets { command.removeTarget(target) }
        targets = []
        library = nil
    }

    deinit {
        for (command,target) in targets { command.removeTarget(target) }
    }
}
