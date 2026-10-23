import AVFoundation
import Combine
import Foundation

private struct SavedLibrary: Codable {
    let version: Int
    let channels: [TVChannel]
    let favorites: [String]
    let recent: [TVChannel]
    let positions: [String: Double]
}

@MainActor
final class MediaLibraryStore: ObservableObject {
    @Published private(set) var channels: [TVChannel] = []
    @Published private(set) var favorites: [String] = []
    @Published private(set) var recent: [TVChannel] = []
    @Published private(set) var positions: [String: Double] = [:]
    @Published private(set) var current: TVChannel?
    @Published private(set) var localFileName: String?
    @Published private(set) var captionText = ""
    @Published private(set) var captionOffset: TimeInterval = 0

    private var currentLocalFile: URL?
    private var captionCues: [CaptionCue] = []
    private var captionObserver: Any?

    let player = AVPlayer()
    @Published private(set) var playbackSpeed: Float = 1.0

    func setPlaybackSpeed(_ speed: Float) {
        let accepted = min(2, max(0.75, speed))
        playbackSpeed = accepted
        player.defaultRate = accepted
        if player.timeControlStatus == .playing { player.rate = accepted }
    }
    private let storageKey = "tv-next-library-v1"
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?

    init() {
        restore()
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 8, preferredTimescale: 600),
            queue: .main
        ) { [weak self] _ in
            self?.savePosition()
        }
        captionObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600),
            queue: .main
        ) { [weak self] _ in
            self?.refreshCaptions()
        }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let captionObserver { player.removeTimeObserver(captionObserver) }
        statusObservation?.invalidate()
        LocalMediaStager.discard(currentLocalFile)
    }

    func importChannels(_ input: [TVChannel]) {
        // Preserve the original order and remove duplicate stream URLs.
        var seen = Set<String>()
        channels = Array(input.filter {
            MediaAddress.valid($0.url) && seen.insert($0.url).inserted
        }.prefix(1500))
        persist()
    }

    func toggleFavorite(_ channel: TVChannel) {
        if favorites.contains(channel.url) {
            favorites.removeAll { $0 == channel.url }
        } else {
            favorites.insert(channel.url, at: 0)
            favorites = Array(favorites.prefix(300))
        }
        persist()
    }

    func isFavorite(_ channel: TVChannel) -> Bool {
        favorites.contains(channel.url)
    }

    func play(_ channel: TVChannel) {
        guard MediaAddress.valid(channel.url), let url = URL(string: channel.url) else { return }
        savePosition()
        player.pause()
        player.replaceCurrentItem(with: nil)
        LocalMediaStager.discard(currentLocalFile)
        currentLocalFile = nil
        localFileName = nil
        clearCaptions()
        statusObservation?.invalidate()
        current = channel
        recent.removeAll { $0.url == channel.url }
        recent.insert(channel, at: 0)
        recent = Array(recent.prefix(100))

        let item = AVPlayerItem(url: url)
        let resume = positions[channel.url]
        if let resume, resume >= 5 {
            statusObservation = item.observe(\.status, options: [.new]) { [weak self] observed, _ in
                guard observed.status == .readyToPlay else { return }
                Task { @MainActor [weak self] in
                    self?.player.seek(to: CMTime(seconds: resume, preferredTimescale: 600))
                }
            }
        }
        player.replaceCurrentItem(with: item)
        player.playImmediately(atRate: playbackSpeed)
        persist()
    }

    func playLocalFile(_ file: URL, name: String) {
        savePosition()
        player.pause()
        player.replaceCurrentItem(with: nil)
        LocalMediaStager.discard(currentLocalFile)
        currentLocalFile = file
        localFileName = name
        current = nil
        clearCaptions()
        statusObservation?.invalidate()
        player.replaceCurrentItem(with: AVPlayerItem(url: file))
        player.playImmediately(atRate: playbackSpeed)
        // Local sandbox files are intentionally NOT added to persistent library/history.
    }

    func setCaptions(_ cues: [CaptionCue]) {
        captionCues = Array(cues.prefix(5_000))
        captionOffset = 0
        refreshCaptions()
    }

    func setCaptionOffset(_ value: TimeInterval) {
        guard value.isFinite else { return }
        captionOffset = max(-10, min(10, value))
        refreshCaptions()
    }

    func clearCaptions() {
        captionCues = []
        captionOffset = 0
        captionText = ""
    }

    private func refreshCaptions() {
        let now = player.currentTime().seconds
        guard now.isFinite else {
            captionText = ""
            return
        }
        let text = CaptionParser.activeText(captionCues, at: now, offset: captionOffset)
        if text != captionText { captionText = text }
    }

    func savePosition() {
        guard let channel = current,
              let duration = player.currentItem?.duration.seconds, duration.isFinite, duration >= 60 else { return }
        let seconds = player.currentTime().seconds
        guard seconds.isFinite, seconds >= 0 else { return }
        if seconds < 5 || duration - seconds < 15 {
            positions.removeValue(forKey: channel.url)
        } else {
            positions[channel.url] = Double(Int(seconds))
        }
        if positions.count > 250 {
            for key in positions.keys.sorted().prefix(positions.count - 250) {
                positions.removeValue(forKey: key)
            }
        }
        persist()
    }

    func clear() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        LocalMediaStager.discard(currentLocalFile)
        currentLocalFile = nil
        localFileName = nil
        clearCaptions()
        statusObservation?.invalidate()
        current = nil
        channels = []
        favorites = []
        recent = []
        positions = [:]
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              data.count <= 2_000_000,
              let saved = try? JSONDecoder().decode(SavedLibrary.self, from: data),
              saved.version == 1 else { return }
        channels = Array(saved.channels.filter { MediaAddress.valid($0.url) }.prefix(1500))
        var seenFavorites = Set<String>()
        favorites = Array(saved.favorites.filter {
            MediaAddress.valid($0) && seenFavorites.insert($0).inserted
        }.prefix(300))
        recent = Array(saved.recent.filter { MediaAddress.valid($0.url) }.prefix(100))
        positions = saved.positions.filter { MediaAddress.valid($0.key) && $0.value.isFinite &&
            $0.value >= 0 && $0.value < 604800 }
    }

    private func persist() {
        let value = SavedLibrary(
            version: 1, channels: channels, favorites: favorites,
            recent: recent, positions: positions
        )
        guard let data = try? JSONEncoder().encode(value), data.count <= 2_000_000 else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
