import AVFoundation
import Combine
import Foundation

private struct SavedLibrary: Codable {
    let version: Int
    let channels: [TVChannel]
    let favorites: [String]
    let recent: [TVChannel]
    let positions: [String: Double]
    let recentTimes: [String:Double]?
}

struct NativeAudioTrack: Identifiable, Equatable {
    let id: Int
    let title: String
}

@MainActor
final class MediaLibraryStore: ObservableObject {
    @Published private(set) var playbackGeneration=0
    @Published private(set) var channels: [TVChannel] = []
    @Published private(set) var favorites: [String] = []
    @Published private(set) var recent: [TVChannel] = []
    @Published private(set) var positions: [String: Double] = [:]
    @Published private(set) var current: TVChannel?
    @Published private(set) var localFileName: String?
    @Published private(set) var playbackError: String?
    @Published private(set) var pictureInPictureActive = false
    private var audioObservers: [NSObjectProtocol] = []
    @Published private(set) var captionText = ""
    @Published private(set) var captionOffset: TimeInterval = 0

    private var recentTimes: [String:Double] = [:]
    private var currentLocalFile: URL?
    private var captionCues: [CaptionCue] = []
    private var captionObserver: Any?

    let player = AVPlayer()
    @Published private(set) var audioTracks: [NativeAudioTrack] = []
    @Published private(set) var selectedAudioTrack: Int?
    private var audioTrackTask: Task<Void, Never>?
    private var audioTrackItem: AVPlayerItem?
    private var audioTrackGroup: AVMediaSelectionGroup?

    /// Media selection is ephemeral and scoped to the installed AVPlayerItem.
    func selectAudioTrack(_ index: Int) -> Bool {
        guard let item = audioTrackItem, player.currentItem === item,
              let group = audioTrackGroup,
              index >= 0, index < audioTracks.count, index < group.options.count else { return false }
        player.appliesMediaSelectionCriteriaAutomatically = false
        item.select(group.options[index], in: group)
        selectedAudioTrack = index
        return true
    }

    private func resetAudioTracks() {
        player.appliesMediaSelectionCriteriaAutomatically = true
        audioTrackTask?.cancel()
        audioTrackTask = nil
        audioTrackItem = nil
        audioTrackGroup = nil
        audioTracks = []
        selectedAudioTrack = nil
    }

    private func discoverAudioTracks(for item: AVPlayerItem) {
        audioTrackTask?.cancel()
        audioTrackTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                guard let group = try await item.asset.loadMediaSelectionGroup(for: .audible),
                      !Task.isCancelled, self.player.currentItem === item else { return }
                self.audioTrackItem = item
                self.audioTrackGroup = group
                self.audioTracks = Array(group.options.prefix(16).enumerated().map { index, option in
                    let label = String(option.displayName.prefix(80))
                    return NativeAudioTrack(id: index, title: "音轨 \(index + 1) · " + (label.isEmpty ? "未命名" : label))
                })
                if let selected = item.currentMediaSelection.selectedMediaOption(in: group) {
                    self.selectedAudioTrack = self.audioTracks.first(where: {
                        group.options[$0.id] === selected
                    })?.id
                } else {
                    self.selectedAudioTrack = nil
                }
            } catch {
                // Some codecs/containers expose no AVFoundation media-selection group.
                // Keep system playback working rather than presenting an unusable menu.
            }
        }
    }

    @Published private(set) var playbackSpeed: Float = 1.0

    func setPlaybackSpeed(_ speed: Float) {
        guard speed.isFinite else { return }
        let accepted = min(2, max(0.75, speed))
        playbackSpeed = accepted
        player.defaultRate = accepted
        if player.timeControlStatus == .playing { player.rate = accepted }
    }
    private let storageKey = "tv-next-library-v1"
    private let defaults: UserDefaults
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var requestedChannel: TVChannel?
    private let createRelay: @MainActor (TVNextAPI, NativeRelayRequest) async throws -> NativeRelayResponse
    private let resolveReplay: @MainActor (TVNextAPI, NativeReplayRequest) async throws -> NativeReplaySession
    private var relayAPI: TVNextAPI?
    private var relayContext=""
    private var relayTask: Task<Void,Never>?
    private var relayGeneration=UUID()
    private var activeRelay: (TVNextAPI,String)?

    func configureRelay(server: String,session: NativeHomeSession?) {
        let context=server+"|"+(session?.token ?? "")
        guard context != relayContext else { return }
        relayContext=context
        savePosition()
        cancelRelay()
        if let session,let url=URL(string:server),["http","https"].contains(url.scheme?.lowercased() ?? "") {
            relayAPI=TVNextAPI(server:url,token:session.token)
        } else { relayAPI=nil }
    }
    private func release(_ api: TVNextAPI,_ ticket: String) {
        Task { let _: [String:Bool]? = try? await api.request("home/media/"+ticket+"/close",body:EmptyHomeRequest()) }
    }
    private func cancelRelay() {
        relayGeneration=UUID();relayTask?.cancel();relayTask=nil
        if let (api,ticket)=activeRelay {
            player.pause();player.replaceCurrentItem(with:nil);resetAudioTracks();release(api,ticket)
        }
        activeRelay=nil
    }

    init(defaults: UserDefaults = .standard,
         createRelay: @escaping @MainActor (TVNextAPI, NativeRelayRequest) async throws -> NativeRelayResponse = { api, request in
             try await api.request("home/media/sessions", body: request)
         }, resolveReplay: @escaping @MainActor (TVNextAPI, NativeReplayRequest) async throws -> NativeReplaySession = { api, request in
             try await api.request("subscriptions/replay", body: request)
         }) {
        self.defaults = defaults
        self.createRelay = createRelay
        self.resolveReplay = resolveReplay
        player.allowsExternalPlayback = true
        restore()
        let center = NotificationCenter.default
        audioObservers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            Task { @MainActor [weak self] in self?.suspendPlayback(force: true) }
        })
        audioObservers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
            Task { @MainActor [weak self] in self?.suspendPlayback(force: true) }
        })
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
        for observer in audioObservers { NotificationCenter.default.removeObserver(observer) }
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let captionObserver { player.removeTimeObserver(captionObserver) }
        statusObservation?.invalidate()
        relayTask?.cancel()
        audioTrackTask?.cancel()
        LocalMediaStager.discard(currentLocalFile)
    }

    @discardableResult
    func importChannels(_ input: [TVChannel]) -> Bool {
        // Preserve the original order and remove duplicate stream URLs.
        var seen = Set<String>()
        let replacement = Array(input.filter {
            MediaAddress.valid($0.url) && seen.insert($0.url).inserted
        }.prefix(1500))
        guard !replacement.isEmpty else { return false }
        channels = replacement
        persist()
        return true
    }

    func toggleFavorite(_ channel: TVChannel) {
        guard MediaAddress.valid(channel.url) else { return }
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
        playbackError = nil
        guard MediaAddress.valid(channel.url), let url = URL(string: channel.url) else { return }
        playbackGeneration += 1
        if let replay = channel.replay {
            guard let api=relayAPI else { playbackError="请先登录家庭服务器以播放回放。";return }
            requestedChannel=channel
            do {
                let address=try MediaRelayAddress.resolve(replay.path,server:api.server)
                guard replay.expiresAt > Int64(Date().timeIntervalSince1970*1000) else { throw NativeRequestError.message("回放会话已过期，请重新选择时间。") }
                savePosition();cancelRelay()
                activeRelay=(api,address.ticket);requestedChannel=channel
                playResolved(channel,address.url)
            } catch { playbackError=error.localizedDescription }
            return
        }
        savePosition()
        cancelRelay()
        statusObservation?.invalidate()
        player.pause()
        player.replaceCurrentItem(with: nil)
        resetAudioTracks()
        requestedChannel = channel
        if channel.headersRequired == true {
            playbackError = "媒体库未保存此来源的私密请求头，请重新加载订阅后播放。"
            return
        }
        if !(channel.headers ?? [:]).isEmpty {
            guard let api=relayAPI else { playbackError="请先登录当前家庭服务器，以适配此来源的播放请求头。";return }
            let generation=relayGeneration
            relayTask=Task { @MainActor in
                do {
                    let result: NativeRelayResponse=try await createRelay(api, NativeRelayRequest(url:channel.url,headers:channel.headers ?? [:]))
                    let address=try MediaRelayAddress.resolve(result.path,server:api.server)
                    guard !Task.isCancelled,relayGeneration==generation else { release(api,address.ticket);return }
                    activeRelay=(api,address.ticket)
                    playResolved(channel,address.url)
                } catch { if !Task.isCancelled,relayGeneration==generation { playbackError=error.localizedDescription } }
            }
            return
        }
        playResolved(channel,url)
    }
    private func playResolved(_ channel: TVChannel,_ url: URL) {
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
        var history=channel;history.replay=nil
        recent.insert(history, at: 0)
        recent = Array(recent.prefix(100))
        recentTimes[channel.url] = Date().timeIntervalSince1970 * 1000
        recentTimes = recentTimes.filter { key,_ in recent.contains(where: { $0.url == key }) }

        guard prepareAudioSession() else { return }
        let item = AVPlayerItem(url: url)
        observe(item, resume: channel.replay == nil ? positions[channel.url] : nil)
        player.replaceCurrentItem(with: item)
        player.playImmediately(atRate: playbackSpeed)
        persist()
    }

    func playLocalFile(_ file: URL, name: String) {
        playbackGeneration += 1
        requestedChannel = nil
        savePosition()
        cancelRelay()
        player.pause()
        player.replaceCurrentItem(with: nil)
        LocalMediaStager.discard(currentLocalFile)
        currentLocalFile = file
        localFileName = name
        current = nil
        clearCaptions()
        statusObservation?.invalidate()
        playbackError = nil
        guard prepareAudioSession() else { return }
        let item = AVPlayerItem(url: file)
        observe(item, resume: nil)
        player.replaceCurrentItem(with: item)
        player.playImmediately(atRate: playbackSpeed)
        // Local sandbox files are intentionally NOT added to persistent library/history.
    }

    /// Status callbacks may arrive after another selection, clear or relay cancellation.
    /// Only the currently installed item may change UI state or seek the player.
    private func observe(_ item: AVPlayerItem, resume: Double?) {
        resetAudioTracks()
        statusObservation?.invalidate()
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] observed, _ in
            Task { @MainActor [weak self] in
                guard let self, self.player.currentItem === observed else { return }
                if observed.status == .failed {
                    self.playbackError = "播放失败：媒体不可访问或编解码不受支持。可重试或选择其他媒体。"
                } else if observed.status == .readyToPlay {
                    self.playbackError = nil
                    self.discoverAudioTracks(for: observed)
                    if let resume, resume.isFinite, resume >= 5 {
                        let duration = observed.duration.seconds
                        guard duration.isFinite, duration >= 60, duration - resume >= 15 else { return }
                        self.player.seek(to: CMTime(seconds: resume, preferredTimescale: 600))
                    }
                }
            }
        }
    }

    func retryPlayback() {
        if let requestedChannel, requestedChannel.replay != nil {
            guard let selection=requestedChannel.replaySelection else {
                playbackError="回放会话不可直接重试，请重新选择回放时间。"
                return
            }
            guard let api=relayAPI else {
                playbackError="请先登录家庭服务器后重试回放。"
                return
            }
            // A closed or expired capability is never reusable. Re-resolve the original
            // user-selected time before installing a new AVPlayerItem.
            cancelRelay()
            let generation=relayGeneration
            relayTask=Task { @MainActor in
                do {
                    let request=NativeReplayRequest(channel:requestedChannel,time:selection.time,
                        stop:selection.stop,timezone:selection.timezone)
                    let fresh=try await resolveReplay(api,request)
                    let address=try MediaRelayAddress.resolve(fresh.path,server:api.server)
                    guard !Task.isCancelled,relayGeneration==generation else {
                        release(api,address.ticket);return
                    }
                    guard fresh.expiresAt > Int64(Date().timeIntervalSince1970*1000) else {
                        release(api,address.ticket)
                        throw NativeRequestError.message("回放会话已过期，请重新选择时间。")
                    }
                    var renewed=requestedChannel
                    renewed.replay=fresh
                    play(renewed)
                } catch {
                    if !Task.isCancelled,relayGeneration==generation { playbackError=error.localizedDescription }
                }
            }
        }
        else if let requestedChannel { play(requestedChannel) }
        else if let file = currentLocalFile, let name = localFileName {
            // Reuse the staged file; playLocalFile would discard it before reopening.
            playbackError = nil
            guard prepareAudioSession() else { return }
            let item = AVPlayerItem(url: file)
            observe(item, resume: nil)
            player.replaceCurrentItem(with: item)
            player.playImmediately(atRate: playbackSpeed)
            localFileName = name
        }
    }

    private func prepareAudioSession() -> Bool {
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playback, mode: .moviePlayback)
            try audio.setActive(true)
            return true
        } catch {
            playbackError = "无法启用媒体音频，请重试播放。"
            return false
        }
    }

    func setPictureInPictureActive(_ active: Bool, appIsBackground: Bool = false) {
        pictureInPictureActive = active
        if !active && appIsBackground { suspendPlayback() }
    }

    /// Ordinary backgrounding pauses. An explicit PiP transition retains its installed item.
    /// Pending requests are invalidated in either case and can never auto-start after suspension.
    func suspendPlayback(force: Bool = false) {
        savePosition()
        relayGeneration = UUID()
        relayTask?.cancel()
        relayTask = nil
        if force || !pictureInPictureActive { player.pause() }
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
        guard let channel = current, channel.replay == nil,
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
        playbackGeneration += 1
        cancelRelay()
        player.pause()
        player.replaceCurrentItem(with: nil)
        resetAudioTracks()
        LocalMediaStager.discard(currentLocalFile)
        currentLocalFile = nil
        localFileName = nil
        clearCaptions()
        statusObservation?.invalidate()
        current = nil
        requestedChannel = nil
        pictureInPictureActive = false
        playbackError = nil
        channels = []
        favorites = []
        recent = []
        recentTimes = [:]
        positions = [:]
        defaults.removeObject(forKey: storageKey)
    }

    private func restore() {
        guard let data = defaults.data(forKey: storageKey),
              data.count <= 2_000_000,
              let saved = try? JSONDecoder().decode(SavedLibrary.self, from: data),
              saved.version == 1 else { return }
        var seenChannels = Set<String>()
        channels = Array(saved.channels.filter { MediaAddress.valid($0.url) && seenChannels.insert($0.url).inserted }.prefix(1500))
        var seenFavorites = Set<String>()
        favorites = Array(saved.favorites.filter {
            MediaAddress.valid($0) && seenFavorites.insert($0).inserted
        }.prefix(300))
        var seenRecent = Set<String>()
        recent = Array(saved.recent.filter { MediaAddress.valid($0.url) && seenRecent.insert($0.url).inserted }.prefix(100))
        recentTimes = (saved.recentTimes ?? [:]).filter { MediaAddress.valid($0.key) && $0.value.isFinite && $0.value >= 0 }
        positions = Dictionary(uniqueKeysWithValues: saved.positions.filter { MediaAddress.valid($0.key) && $0.value.isFinite &&
            $0.value >= 0 && $0.value < 604800 }.sorted { $0.key < $1.key }.prefix(250).map { ($0.key, $0.value) })
    }

    func syncedSnapshot() -> NativeLibrarySnapshot {
        NativeLibrarySnapshot(version:1,channels:channels.map(safeSnapshot),favorites:favorites,
            recent:recent.map { NativeRecent(channel:safeSnapshot($0),openedAt:recentTimes[$0.url] ?? 0) },positions:positions)
    }
    func restoreSnapshot(_ value: NativeLibrarySnapshot) throws {
        guard value.version == 1,value.channels.count<=1500,value.favorites.count<=300,value.recent.count<=100,value.positions.count<=250 else { throw NativeRequestError.message("备份版本或数量无效") }
        channels=Array(value.channels.filter { MediaAddress.valid($0.url) }.prefix(1500))
        favorites=Array(value.favorites.filter { MediaAddress.valid($0) }.prefix(300))
        recent=Array(value.recent.filter { MediaAddress.valid($0.channel.url) && $0.openedAt.isFinite && $0.openedAt>=0 }.map(\.channel).prefix(100))
        recentTimes=Dictionary(value.recent.map { ($0.channel.url,$0.openedAt) },uniquingKeysWith:max)
        positions=value.positions.filter { MediaAddress.valid($0.key) && $0.value.isFinite && $0.value>=0 && $0.value<604800 }
        persist()
    }
    private func safeSnapshot(_ channel: TVChannel) -> TVChannel {
        var result = channel
        result.headersRequired = channel.headersRequired == true || !(channel.headers ?? [:]).isEmpty
        result.headers = nil
        result.replay = nil
        result.replaySelection = nil
        result.timeshift = nil
        result.catchup = nil
        return result
    }
    private func persist() {
        let value = SavedLibrary(
            version: 1, channels: channels.map(safeSnapshot), favorites: favorites,
            recent: recent.map(safeSnapshot), positions: positions, recentTimes: recentTimes
        )
        guard let data = try? JSONEncoder().encode(value), data.count <= 2_000_000 else { return }
        defaults.set(data, forKey: storageKey)
    }
}
