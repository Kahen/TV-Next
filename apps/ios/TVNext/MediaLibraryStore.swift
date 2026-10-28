import AVFoundation
import Combine
import CryptoKit
import Foundation

private struct SavedLibrary: Codable {
    let version: Int
    let channels: [TVChannel]
    let favorites: [String]
    let recent: [TVChannel]
    let positions: [String: Double]
    let recentTimes: [String:Double]?
}

private struct NativeAudioPreference: Codable {
    let urlDigest: String
    let displayName: String
    let languageTag: String?
}

private struct NativeAudioPreferenceSnapshot: Codable {
    let version: Int
    let entries: [NativeAudioPreference]
}

private struct NativeSubtitlePreference: Codable {
    let urlDigest: String
    let displayName: String?
    let languageTag: String?
    let isOff: Bool
}

private struct NativeSubtitlePreferenceSnapshot: Codable {
    let version: Int
    let entries: [NativeSubtitlePreference]
}

struct NativeAudioTrack: Identifiable, Equatable {
    let id: Int
    let title: String
}

struct NativeSubtitleTrack: Identifiable, Equatable {
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
    @Published private(set) var backgroundPlaybackEnabled = false
    @Published private(set) var applicationInBackground = false
    private let backgroundStorageKey = "tv-next-background-audio-v1"
    private var mediaControls: NativeMediaControls?
    private var rateObservation: NSKeyValueObservation?
    private var mediaTimeObserver: Any?
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
    private let audioPreferenceStorageKey = "tv-next-native-audio-preferences-v1"
    private var audioPreferences: [NativeAudioPreference] = []

    private func mediaPreferenceKey() -> String? {
        guard let channel = current, channel.replay == nil, currentLocalFile == nil,
              MediaAddress.valid(channel.url) else { return nil }
        return SHA256.hash(data: Data(channel.url.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    private func restoreAudioPreferences() {
        guard let data = defaults.data(forKey: audioPreferenceStorageKey), data.count <= 64_000,
              let snapshot = try? JSONDecoder().decode(NativeAudioPreferenceSnapshot.self, from: data),
              snapshot.version == 1 else { return }
        var seen = Set<String>()
        audioPreferences = Array(snapshot.entries.reversed().filter { entry in
            entry.urlDigest.count == 64 && entry.urlDigest.allSatisfy(\.isHexDigit) &&
            !entry.displayName.isEmpty && entry.displayName.count <= 80 &&
            (entry.languageTag?.count ?? 0) <= 64 &&
            seen.insert(entry.urlDigest).inserted
        }.prefix(100).reversed())
    }

    /// The menu may abbreviate labels, but the saved identity must be complete.
    /// Truncated names could otherwise select a different provider rendition.
    static func persistableAudioDisplayName(_ name: String) -> String? {
        guard !name.isEmpty, name.count <= 80 else { return nil }
        return name
    }

    /// Match full AVFoundation identities, never menu labels or stale indices.
    /// Duplicate name/language pairs are ambiguous and must not auto-select.
    static func uniqueAudioPreferenceIndex(
        in options: [(name: String, languageTag: String?)],
        name: String, languageTag: String?
    ) -> Int? {
        guard persistableAudioDisplayName(name) != nil else { return nil }
        let matches = options.enumerated().filter {
            $0.element.name == name && $0.element.languageTag == languageTag
        }
        return matches.count == 1 ? matches[0].offset : nil
    }

    private func rememberAudioPreference(_ option: AVMediaSelectionOption) {
        guard let key = mediaPreferenceKey() else { return }
        let name = Self.persistableAudioDisplayName(option.displayName)
        let languageTag = option.extendedLanguageTag
        // An unpersistable explicit choice must also invalidate any previous
        // choice for this title, rather than restoring a now-stale track later.
        let saved = name != nil && (languageTag?.count ?? 0) <= 64
            ? [NativeAudioPreference(urlDigest: key, displayName: name!, languageTag: languageTag)]
            : []
        let updated = Array((audioPreferences.filter { $0.urlDigest != key } + saved).suffix(100))
        let snapshot = NativeAudioPreferenceSnapshot(version: 1, entries: updated)
        guard let data = try? JSONEncoder().encode(snapshot), data.count <= 64_000 else { return }
        defaults.set(data, forKey: audioPreferenceStorageKey)
        audioPreferences = updated
    }
    @Published private(set) var subtitleTracks: [NativeSubtitleTrack] = []
    @Published private(set) var selectedSubtitleTrack: Int?
    @Published private(set) var canDisableEmbeddedSubtitles = false
    private var subtitleTrackTask: Task<Void, Never>?
    private var subtitleTrackItem: AVPlayerItem?
    private var subtitleTrackGroup: AVMediaSelectionGroup?
    private let subtitlePreferenceStorageKey = "tv-next-native-subtitle-preferences-v1"
    private var subtitlePreferences: [NativeSubtitlePreference] = []

    private func restoreSubtitlePreferences() {
        guard let data = defaults.data(forKey: subtitlePreferenceStorageKey),
              data.count <= 64_000,
              let snapshot = try? JSONDecoder().decode(NativeSubtitlePreferenceSnapshot.self, from: data),
              snapshot.version == 1 else { return }
        var seen = Set<String>()
        subtitlePreferences = Array(snapshot.entries.reversed().filter { entry in
            let validChoice = entry.isOff
                ? entry.displayName == nil && entry.languageTag == nil
                : (entry.displayName.map { !$0.isEmpty && $0.count <= 80 } ?? false)
                    && (entry.languageTag?.count ?? 0) <= 64
            return entry.urlDigest.count == 64 && entry.urlDigest.allSatisfy(\.isHexDigit)
                && validChoice && seen.insert(entry.urlDigest).inserted
        }.prefix(100).reversed())
    }

    /// Display labels may be shortened for the menu, but a persisted identity
    /// must never be shortened: two provider renditions can share the same prefix.
    static func persistableSubtitleDisplayName(_ name: String) -> String? {
        guard !name.isEmpty, name.count <= 80 else { return nil }
        return name
    }

    private func rememberSubtitlePreference(_ option: AVMediaSelectionOption?) {
        guard let key = mediaPreferenceKey() else { return }
        let name = option.flatMap { Self.persistableSubtitleDisplayName($0.displayName) }
        guard option == nil || (name != nil
              && (option?.extendedLanguageTag?.count ?? 0) <= 64) else { return }
        let preference = NativeSubtitlePreference(urlDigest: key,
            displayName: name, languageTag: option?.extendedLanguageTag, isOff: option == nil)
        let updated = Array((subtitlePreferences.filter { $0.urlDigest != key } + [preference]).suffix(100))
        let snapshot = NativeSubtitlePreferenceSnapshot(version: 1, entries: updated)
        guard let data = try? JSONEncoder().encode(snapshot), data.count <= 64_000 else { return }
        defaults.set(data, forKey: subtitlePreferenceStorageKey)
        subtitlePreferences = updated
    }

    /// Only the installed item may receive a legible-track selection.
    /// nil explicitly disables subtitles when the media group permits it.
    func selectSubtitleTrack(_ index: Int?) -> Bool {
        guard let item = subtitleTrackItem, player.currentItem === item,
              let group = subtitleTrackGroup else { return false }
        if let index {
            guard index >= 0, index < subtitleTracks.count,
                  index < group.options.count else { return false }
            player.appliesMediaSelectionCriteriaAutomatically = false
            item.select(group.options[index], in: group)
            selectedSubtitleTrack = index
            rememberSubtitlePreference(group.options[index])
        } else {
            guard group.allowsEmptySelection else { return false }
            player.appliesMediaSelectionCriteriaAutomatically = false
            item.select(nil, in: group)
            selectedSubtitleTrack = nil
            rememberSubtitlePreference(nil)
        }
        return true
    }

    private func discoverEmbeddedSubtitles(for item: AVPlayerItem) {
        subtitleTrackTask?.cancel()
        subtitleTrackTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                guard let group = try await item.asset.loadMediaSelectionGroup(for: .legible),
                      !Task.isCancelled, self.player.currentItem === item else { return }
                self.subtitleTrackItem = item
                self.subtitleTrackGroup = group
                self.canDisableEmbeddedSubtitles = group.allowsEmptySelection
                self.subtitleTracks = Array(group.options.prefix(16).enumerated().map { index, option in
                    let label = String(option.displayName.prefix(80))
                    return NativeSubtitleTrack(id: index,
                        title: "字幕 \(index + 1) · " + (label.isEmpty ? "未命名" : label))
                })
                if let selected = item.currentMediaSelection.selectedMediaOption(in: group) {
                    self.selectedSubtitleTrack = self.subtitleTracks.first(where: {
                        group.options[$0.id] === selected
                    })?.id
                } else {
                    self.selectedSubtitleTrack = nil
                }
                // Restore only an exact, unique identity on the currently installed item.
                if let key = self.mediaPreferenceKey(),
                   let preference = self.subtitlePreferences.first(where: { $0.urlDigest == key }) {
                    if preference.isOff {
                        if group.allowsEmptySelection {
                            self.player.appliesMediaSelectionCriteriaAutomatically = false
                            item.select(nil, in: group)
                            self.selectedSubtitleTrack = nil
                        }
                    } else {
                        let matches = Array(group.options.prefix(16).enumerated()).filter {
                            $0.element.displayName == preference.displayName &&
                            $0.element.extendedLanguageTag == preference.languageTag
                        }
                        if matches.count == 1, let match = matches.first {
                            self.player.appliesMediaSelectionCriteriaAutomatically = false
                            item.select(match.element, in: group)
                            self.selectedSubtitleTrack = match.offset
                        }
                    }
                }
            } catch {
                // No selectable legible group: retain native playback and external caption support.
            }
        }
    }

    /// Media selection is ephemeral and scoped to the installed AVPlayerItem.
    func selectAudioTrack(_ index: Int) -> Bool {
        guard let item = audioTrackItem, player.currentItem === item,
              let group = audioTrackGroup,
              index >= 0, index < audioTracks.count, index < group.options.count else { return false }
        player.appliesMediaSelectionCriteriaAutomatically = false
        item.select(group.options[index], in: group)
        selectedAudioTrack = index
        rememberAudioPreference(group.options[index])
        return true
    }

    private func resetMediaSelections() {
        subtitleTrackTask?.cancel()
        subtitleTrackTask = nil
        subtitleTrackItem = nil
        subtitleTrackGroup = nil
        subtitleTracks = []
        selectedSubtitleTrack = nil
        canDisableEmbeddedSubtitles = false
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
                // Reapply only a unique, exact match. Never use a stale numeric index.
                if let key = self.mediaPreferenceKey(),
                   let preference = self.audioPreferences.first(where: { $0.urlDigest == key }) {
                    let options = Array(group.options.prefix(16))
                    if let index = Self.uniqueAudioPreferenceIndex(
                        in: options.map { (name: $0.displayName, languageTag: $0.extendedLanguageTag) },
                        name: preference.displayName, languageTag: preference.languageTag
                    ) {
                        self.player.appliesMediaSelectionCriteriaAutomatically = false
                        item.select(options[index], in: group)
                        self.selectedAudioTrack = index
                    }
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
        updateSystemMetadata()
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
            player.pause();player.replaceCurrentItem(with:nil);resetMediaSelections();release(api,ticket)
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
        restoreAudioPreferences()
        restoreSubtitlePreferences()
        setBackgroundPlaybackEnabled(defaults.bool(forKey: backgroundStorageKey))
        rateObservation = player.observe(\.rate, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.updateSystemMetadata() }
        }
        mediaTimeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateSystemMetadata() }
        }
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
            Task { @MainActor [weak self] in self?.savePosition() }
        }
        captionObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600),
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshCaptions() }
        }
    }

    deinit {
        for observer in audioObservers { NotificationCenter.default.removeObserver(observer) }
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let captionObserver { player.removeTimeObserver(captionObserver) }
        if let mediaTimeObserver { player.removeTimeObserver(mediaTimeObserver) }
        rateObservation?.invalidate()
        statusObservation?.invalidate()
        relayTask?.cancel()
        audioTrackTask?.cancel()
        subtitleTrackTask?.cancel()
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
        resetMediaSelections()
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
        activateSystemControls()
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
        activateSystemControls()
        // Local sandbox files are intentionally NOT added to persistent library/history.
    }

    /// Status callbacks may arrive after another selection, clear or relay cancellation.
    /// Only the currently installed item may change UI state or seek the player.
    private func observe(_ item: AVPlayerItem, resume: Double?) {
        resetMediaSelections()
        statusObservation?.invalidate()
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] observed, _ in
            Task { @MainActor [weak self] in
                guard let self, self.player.currentItem === observed else { return }
                if observed.status == .failed {
                    self.playbackError = "播放失败：媒体不可访问或编解码不受支持。可重试或选择其他媒体。"
                    self.updateSystemMetadata()
                } else if observed.status == .readyToPlay {
                    self.playbackError = nil
                    self.updateSystemMetadata()
                    self.discoverAudioTracks(for: observed)
                    self.discoverEmbeddedSubtitles(for: observed)
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
            activateSystemControls()
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
        if !active && appIsBackground { setApplicationBackground(true) }
    }

    func setBackgroundPlaybackEnabled(_ enabled: Bool) {
        backgroundPlaybackEnabled = enabled
        defaults.set(enabled,forKey:backgroundStorageKey)
        player.audiovisualBackgroundPlaybackPolicy = enabled ? .continuesIfPossible : .automatic
        if !enabled && applicationInBackground && !pictureInPictureActive { player.pause() }
        updateSystemMetadata()
    }

    func setApplicationBackground(_ background: Bool) {
        applicationInBackground = background
        if background { suspendPlayback() }
        else { updateSystemMetadata() }
    }

    /// Opt-in background audio and explicit PiP retain the installed item.
    /// Pending requests are invalidated in either case and can never auto-start after suspension.
    func suspendPlayback(force: Bool = false) {
        savePosition()
        relayGeneration = UUID()
        relayTask?.cancel()
        relayTask = nil
        if force || !(pictureInPictureActive || backgroundPlaybackEnabled && applicationInBackground) { player.pause() }
        updateSystemMetadata()
    }

    private func activateSystemControls() {
        if mediaControls == nil { mediaControls = NativeMediaControls() }
        mediaControls?.activate(self)
        updateSystemMetadata()
    }

    private func updateSystemMetadata() {
        guard let item = player.currentItem, item.status != .failed else { mediaControls?.publish(nil);return }
        let snapshot = NativeNowPlayingSnapshot(title:localFileName ?? current?.name ?? "TV-Next 媒体",
            elapsed:player.currentTime().seconds,duration:item.duration.seconds,rate:player.rate,defaultRate:playbackSpeed)
        mediaControls?.publish(snapshot)
    }

    @discardableResult
    func handleSystemPlaybackCommand(_ command: NativePlaybackCommand) -> Bool {
        guard let item = player.currentItem, item.status != .failed else { return false }
        switch command {
        case .play:
            guard item.status == .readyToPlay,
                  !applicationInBackground || backgroundPlaybackEnabled || pictureInPictureActive,
                  prepareAudioSession() else { return false }
            player.playImmediately(atRate:playbackSpeed)
        case .pause:
            player.pause();savePosition()
        case .toggle:
            return handleSystemPlaybackCommand(player.rate > 0 || player.timeControlStatus == .waitingToPlayAtSpecifiedRate ? .pause : .play)
        case .seek(let value):
            let duration=item.duration.seconds
            guard value.isFinite,value >= 0,duration.isFinite,duration > 0,duration < 604_800,value <= duration else { return false }
            player.seek(to:CMTime(seconds:value,preferredTimescale:600),toleranceBefore:.zero,toleranceAfter:.zero) { [weak self,weak item] finished in
                Task { @MainActor [weak self,weak item] in
                    guard finished,let self,let item,self.player.currentItem === item else { return }
                    self.updateSystemMetadata()
                }
            }
        case .skip(let interval):
            let current=player.currentTime().seconds,duration=item.duration.seconds
            guard interval.isFinite,abs(interval)<=60,current.isFinite,duration.isFinite,duration>0 else { return false }
            return handleSystemPlaybackCommand(.seek(min(duration,max(0,current+interval))))
        case .rate(let rate):
            let duration=item.duration.seconds
            guard rate.isFinite,(0.75...2).contains(rate),duration.isFinite,duration>0,duration<604_800 else { return false }
            setPlaybackSpeed(rate)
        }
        updateSystemMetadata()
        return true
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
        resetMediaSelections()
        LocalMediaStager.discard(currentLocalFile)
        currentLocalFile = nil
        localFileName = nil
        clearCaptions()
        statusObservation?.invalidate()
        current = nil
        requestedChannel = nil
        pictureInPictureActive = false
        mediaControls?.invalidate()
        backgroundPlaybackEnabled = false
        player.audiovisualBackgroundPlaybackPolicy = .automatic
        defaults.removeObject(forKey:backgroundStorageKey)
        playbackError = nil
        channels = []
        favorites = []
        recent = []
        recentTimes = [:]
        positions = [:]
        defaults.removeObject(forKey: storageKey)
        audioPreferences = []
        defaults.removeObject(forKey: audioPreferenceStorageKey)
        subtitlePreferences = []
        defaults.removeObject(forKey: subtitlePreferenceStorageKey)
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
