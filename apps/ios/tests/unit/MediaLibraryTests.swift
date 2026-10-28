import XCTest
import AVFoundation
import AVKit
import CryptoKit
import MediaPlayer
@testable import TVNext

@MainActor
final class MediaLibraryTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!
    private var store: MediaLibraryStore!

    override func setUp() async throws {
        suite = "TVNextTests-" + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
        store = MediaLibraryStore(defaults: defaults)
    }

    override func tearDown() async throws {
        store.clear()
        store = nil
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
    }

    private func channel(_ name: String = "Fixture", url: String = "https://example.invalid/movie.mp4") -> TVChannel {
        TVChannel(name: name, url: url, group: "Test", logo: nil, tvgId: nil)
    }

    private func fixture() throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: "fixture", withExtension: "mp4"))
    }

    private func waitUntil(_ condition: @escaping () -> Bool, timeout: TimeInterval = 10) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertTrue(condition(), "AVPlayer did not reach the expected state")
    }

    func testSystemAirPlayIsAllowedForAVPlayer() {
        // A simulator may not advertise any actual AirPlay destination.
        // Verify only that the production player permits the system route.
        XCTAssertTrue(store.player.allowsExternalPlayback)
    }

    func testOnlyServerApprovedAndroidSpiderSitesAreEnabled() throws {
        func site(_ support: String) throws -> NativeSubscription.Site {
            try JSONDecoder().decode(NativeSubscription.Site.self, from: Data("{\"key\":\"fixture\",\"name\":\"Fixture\",\"type\":3,\"searchable\":true,\"hidden\":false,\"support\":\"\(support)\"}".utf8))
        }
        XCTAssertTrue(try site("android-spider").supported)
        XCTAssertFalse(try site("requires-spider-runtime").supported)
        XCTAssertFalse(try site("unknown-runtime").supported)
        XCTAssertNotNil(NativeSubscriptionURLStore.validated("http://www.饭太硬.net/tv"))
    }

    func testOptInBackgroundAudioPersistsAndInterruptionStillPauses() async throws {
        XCTAssertFalse(store.backgroundPlaybackEnabled)
        store.playLocalFile(try fixture(), name:"Owned fixture.mp4")
        try await waitUntil { self.store.player.currentItem?.status == .readyToPlay && self.store.player.rate > 0 }
        store.setApplicationBackground(true)
        XCTAssertEqual(store.player.rate,0,"Backgrounding remains opt-in")
        XCTAssertFalse(store.handleSystemPlaybackCommand(.play))
        store.setBackgroundPlaybackEnabled(true)
        XCTAssertTrue(store.handleSystemPlaybackCommand(.play))
        XCTAssertEqual(store.player.audiovisualBackgroundPlaybackPolicy,.continuesIfPossible)
        let restored=MediaLibraryStore(defaults:defaults)
        XCTAssertTrue(restored.backgroundPlaybackEnabled)
        store.setApplicationBackground(true)
        XCTAssertGreaterThan(store.player.rate,0)
        NotificationCenter.default.post(name:AVAudioSession.interruptionNotification,object:nil,
            userInfo:[AVAudioSessionInterruptionTypeKey:AVAudioSession.InterruptionType.began.rawValue])
        try await waitUntil { self.store.player.rate == 0 }
        XCTAssertTrue(store.handleSystemPlaybackCommand(.play))
        store.setBackgroundPlaybackEnabled(false)
        XCTAssertEqual(store.player.rate,0)
        XCTAssertFalse(store.handleSystemPlaybackCommand(.play))
        store.clear()
        XCTAssertNil(defaults.object(forKey:"tv-next-background-audio-v1"))
    }

    func testRemoteTransportCommandsValidateSeekAndPublishOnlyMetadata() async throws {
        XCTAssertFalse(store.handleSystemPlaybackCommand(.play))
        XCTAssertFalse(store.handleSystemPlaybackCommand(.seek(1)))
        store.playLocalFile(try fixture(),name:"Owned fixture.mp4")
        try await waitUntil { self.store.player.currentItem?.status == .readyToPlay }
        XCTAssertTrue(store.handleSystemPlaybackCommand(.pause))
        XCTAssertEqual(store.player.rate,0)
        let duration=try XCTUnwrap(store.player.currentItem).duration.seconds
        for invalid in [-1,Double.nan,Double.infinity,duration+1] {
            XCTAssertFalse(store.handleSystemPlaybackCommand(.seek(invalid)))
        }
        XCTAssertFalse(store.handleSystemPlaybackCommand(.skip(.nan)))
        XCTAssertFalse(store.handleSystemPlaybackCommand(.skip(61)))
        XCTAssertTrue(store.handleSystemPlaybackCommand(.seek(1)))
        try await waitUntil { abs(self.store.player.currentTime().seconds-1) < 0.1 }
        XCTAssertFalse(store.handleSystemPlaybackCommand(.rate(.nan)))
        XCTAssertFalse(store.handleSystemPlaybackCommand(.rate(3)))
        XCTAssertTrue(store.handleSystemPlaybackCommand(.rate(1.5)))
        XCTAssertTrue(store.handleSystemPlaybackCommand(.play))
        XCTAssertEqual(store.player.rate,1.5)
        try await waitUntil { (MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] as? String) == "Owned fixture.mp4" }
        let info=try XCTUnwrap(MPNowPlayingInfoCenter.default().nowPlayingInfo)
        XCTAssertNil(info[MPMediaItemPropertyAssetURL])
        XCTAssertFalse(String(describing:info).contains("file://"))
        XCTAssertTrue(MPRemoteCommandCenter.shared().changePlaybackPositionCommand.isEnabled)
        XCTAssertTrue(store.handleSystemPlaybackCommand(.toggle))
        XCTAssertEqual(store.player.rate,0)
        store.clear()
        XCTAssertNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)
        XCTAssertFalse(MPRemoteCommandCenter.shared().playCommand.isEnabled)
    }

    func testNowPlayingSnapshotBoundsAndOldStoreCannotOverwriteNewOwner() async throws {
        let live=NativeNowPlayingSnapshot(title:"https://example.invalid/private?token=secret",elapsed:.nan,duration:.infinity,rate:.infinity,defaultRate:.nan)
        XCTAssertFalse(live.seekable)
        XCTAssertEqual(live.info[MPMediaItemPropertyTitle] as? String,"TV-Next 媒体")
        XCTAssertNil(live.info[MPMediaItemPropertyPlaybackDuration])
        XCTAssertNil(live.info[MPNowPlayingInfoPropertyElapsedPlaybackTime])
        XCTAssertEqual((live.info[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber)?.floatValue,0)
        XCTAssertEqual((live.info[MPNowPlayingInfoPropertyDefaultPlaybackRate] as? NSNumber)?.floatValue,1)
        store.playLocalFile(try fixture(),name:"Old title")
        let next=MediaLibraryStore(defaults:defaults)
        defer { next.clear() }
        next.playLocalFile(try fixture(),name:"New title")
        try await waitUntil { (MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] as? String) == "New title" }
        store.setPlaybackSpeed(2)
        store.clear()
        XCTAssertEqual(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] as? String,"New title")
        next.clear()
        XCTAssertNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)
    }

    func testSubscriptionKeychainOnlyStoresValidExplicitURLsAndCanClear() {
        let store = NativeSubscriptionURLStore(account: "xcuitest-" + UUID().uuidString)
        defer { _ = store.clear() }
        XCTAssertNil(store.read())
        for invalid in [
            "javascript:alert(1)", "file:///secret", "https://a:b@example.org/config",
            "https://example.org/\\\\@another.example/", "https://example.org/config#token",
            "https://example.org/space here", "https://example.org/" + String(repeating: "x", count: 5000)
        ] { XCTAssertFalse(store.save(invalid), "Unexpectedly persisted an unsafe URL") }
        let first = "https://example.org/config.json?token=synthetic"
        let second = "http://192.168.2.10:8080/config.json"
        XCTAssertTrue(store.save(first))
        XCTAssertEqual(store.read(), first)
        XCTAssertFalse(store.save("https://user:pass@example.org/unsafe"))
        XCTAssertEqual(store.read(), first, "Invalid updates must not replace a saved URL")
        XCTAssertTrue(store.save(second), "Expected in-place Keychain update")
        XCTAssertEqual(store.read(), second)
        XCTAssertTrue(store.clear())
        XCTAssertTrue(store.clear(), "Clearing an absent Keychain item should be idempotent")
        XCTAssertNil(store.read())
    }

    func testEmptyOrInvalidImportPreservesLibraryAndDeduplicates() {
        let original = channel()
        XCTAssertTrue(store.importChannels([original, original]))
        XCTAssertFalse(store.importChannels([]))
        XCTAssertFalse(store.importChannels([channel(url: "file:///private/movie.mp4")]))
        XCTAssertEqual(store.channels, [original])
        let restored = MediaLibraryStore(defaults: defaults)
        XCTAssertEqual(restored.channels.map(\.url), [original.url])
        XCTAssertEqual(restored.channels.first?.name, original.name)
        XCTAssertEqual(restored.channels.first?.group, original.group)
        XCTAssertNotEqual(restored.channels.first?.headersRequired, true)
    }

    func testPersistenceDoesNotSavePrivateHeadersAndRetainsFavoritesAndResume() throws {
        var source = channel()
        source.headers = ["Authorization": "private-test-secret"]
        XCTAssertTrue(store.importChannels([source]))
        store.toggleFavorite(source)
        try store.restoreSnapshot(NativeLibrarySnapshot(version: 1, channels: [source], favorites: [source.url],
            recent: [NativeRecent(channel: source, openedAt: 123)], positions: [source.url: 20]))
        let restored = MediaLibraryStore(defaults: defaults)
        XCTAssertEqual(restored.favorites, [source.url])
        XCTAssertEqual(restored.positions[source.url], 20)
        XCTAssertEqual(restored.recent.first?.url, source.url)
        XCTAssertNil(restored.channels.first?.headers)
        XCTAssertEqual(restored.channels.first?.headersRequired, true)
        let bytes = try XCTUnwrap(defaults.data(forKey: "tv-next-library-v1"))
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("private-test-secret"))
        restored.play(try XCTUnwrap(restored.channels.first))
        XCTAssertNotNil(restored.playbackError)
        XCTAssertNil(restored.player.currentItem)
    }

    func testAudioTrackSelectionIsItemScopedAndRejectsInvalidIndices() async throws {
        XCTAssertFalse(store.selectAudioTrack(0), "No player item must never accept a track")
        // An HLS master explicitly declares two alternative audio renditions.
        // A multi-audio MP4 does not consistently expose AVMediaSelectionGroup on iOS.
        store.play(channel("Two audio renditions", url: "http://127.0.0.1:8766/master.m3u8"))
        try await waitUntil({ self.store.audioTracks.count == 2 }, timeout: 15)
        XCTAssertFalse(store.selectAudioTrack(-1))
        XCTAssertFalse(store.selectAudioTrack(2))
        XCTAssertTrue(store.selectAudioTrack(1))
        XCTAssertFalse(store.player.appliesMediaSelectionCriteriaAutomatically)
        XCTAssertEqual(store.selectedAudioTrack, 1)
        XCTAssertEqual(store.audioTracks.map(\.id), [0, 1])
        store.playLocalFile(try fixture(), name: "fixture.mp4")
        XCTAssertTrue(store.audioTracks.isEmpty, "Old item tracks must disappear immediately")
        XCTAssertTrue(store.player.appliesMediaSelectionCriteriaAutomatically)
        XCTAssertNil(store.selectedAudioTrack)
        XCTAssertFalse(store.selectAudioTrack(1), "Do not select a track from a replaced item")
        store.clear()
        XCTAssertTrue(store.audioTracks.isEmpty)
    }

    func testPerTitleAudioChoiceRestoresWithoutPersistingMediaURL() async throws {
        let mediaURL = "http://127.0.0.1:8766/master.m3u8"
        XCTAssertFalse(store.selectAudioTrack(1))
        store.play(channel("Synthetic HLS", url: mediaURL))
        try await waitUntil({ self.store.audioTracks.count == 2 }, timeout: 15)
        XCTAssertFalse(store.selectAudioTrack(99))
        XCTAssertNil(defaults.data(forKey: "tv-next-native-audio-preferences-v1"))
        XCTAssertTrue(store.selectAudioTrack(1))
        let bytes = try XCTUnwrap(defaults.data(forKey: "tv-next-native-audio-preferences-v1"))
        XCTAssertLessThanOrEqual(bytes.count, 64_000)
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains(mediaURL),
                       "Only a URL digest, never the media URL, may be stored")
        let restored = MediaLibraryStore(defaults: defaults)
        restored.play(channel("Synthetic HLS", url: mediaURL))
        try await waitUntil({ restored.audioTracks.count == 2 && restored.selectedAudioTrack == 1 },
                            timeout: 15)
        XCTAssertFalse(restored.player.appliesMediaSelectionCriteriaAutomatically,
                       "The saved exact track match must be actively restored")
        restored.playLocalFile(try fixture(), name: "fixture.mp4")
        XCTAssertTrue(restored.player.appliesMediaSelectionCriteriaAutomatically,
                      "Unrelated local files must not inherit an HLS preference")
        restored.clear()
        XCTAssertNil(defaults.data(forKey: "tv-next-native-audio-preferences-v1"))
    }

    func testAudioPreferenceIdentityNeverTruncatesOrMatchesAmbiguousNames() {
        let prefix = String(repeating: "A", count: 80)
        let first = prefix + " - English"
        let second = prefix + " - Commentary"
        XCTAssertNotEqual(first, second)
        XCTAssertNil(MediaLibraryStore.persistableAudioDisplayName(first))
        XCTAssertNil(MediaLibraryStore.persistableAudioDisplayName(second))
        XCTAssertEqual(MediaLibraryStore.persistableAudioDisplayName(prefix), prefix)
        XCTAssertNil(MediaLibraryStore.persistableAudioDisplayName(""))
        XCTAssertNil(MediaLibraryStore.persistableAudioDisplayName(String(repeating: "x", count: 81)))

        let longOptions: [(name: String, languageTag: String?)] = [
            (name: first, languageTag: "en"),
            (name: second, languageTag: "en")
        ]
        // A legacy truncated preference must not select either long rendition.
        XCTAssertNil(MediaLibraryStore.uniqueAudioPreferenceIndex(
            in: longOptions, name: prefix, languageTag: "en"))
        XCTAssertNil(MediaLibraryStore.uniqueAudioPreferenceIndex(
            in: longOptions, name: first, languageTag: "en"))

        let options: [(name: String, languageTag: String?)] = [
            (name: "Original", languageTag: "en"),
            (name: "Original", languageTag: "fr"),
            (name: "Commentary", languageTag: "en")
        ]
        XCTAssertEqual(MediaLibraryStore.uniqueAudioPreferenceIndex(
            in: options, name: "Original", languageTag: "fr"), 1)
        XCTAssertEqual(MediaLibraryStore.uniqueAudioPreferenceIndex(
            in: options, name: "Commentary", languageTag: "en"), 2)
        XCTAssertNil(MediaLibraryStore.uniqueAudioPreferenceIndex(
            in: options, name: "Original", languageTag: nil))
        XCTAssertNil(MediaLibraryStore.uniqueAudioPreferenceIndex(
            in: options + [(name: "Original", languageTag: "en")],
            name: "Original", languageTag: "en"))
    }

    func testCorruptedAudioPreferenceIsIgnoredWithoutChangingPlayback() async throws {
        defaults.set(Data("not-json".utf8), forKey: "tv-next-native-audio-preferences-v1")
        let restored = MediaLibraryStore(defaults: defaults)
        restored.play(channel("Synthetic HLS", url: "http://127.0.0.1:8766/master.m3u8"))
        try await waitUntil({ restored.audioTracks.count == 2 }, timeout: 15)
        XCTAssertTrue(restored.player.appliesMediaSelectionCriteriaAutomatically)
    }

    func testEmbeddedHlsSubtitlesAreItemScopedAndCanBeDisabled() async throws {
        XCTAssertFalse(store.selectSubtitleTrack(0), "No installed item must reject selection")
        XCTAssertFalse(store.selectSubtitleTrack(nil), "No installed item must reject off")
        // The loopback-only HLS master declares one synthetic WebVTT rendition.
        store.play(channel("Synthetic subtitle rendition", url: "http://127.0.0.1:8766/master.m3u8"))
        try await waitUntil({ self.store.subtitleTracks.count == 1 }, timeout: 15)
        XCTAssertFalse(store.selectSubtitleTrack(-1))
        XCTAssertFalse(store.selectSubtitleTrack(1))
        XCTAssertTrue(store.selectSubtitleTrack(0))
        XCTAssertEqual(store.selectedSubtitleTrack, 0)
        XCTAssertFalse(store.player.appliesMediaSelectionCriteriaAutomatically)
        XCTAssertTrue(store.canDisableEmbeddedSubtitles)
        XCTAssertTrue(store.selectSubtitleTrack(nil))
        XCTAssertNil(store.selectedSubtitleTrack)
        store.playLocalFile(try fixture(), name: "fixture.mp4")
        XCTAssertTrue(store.subtitleTracks.isEmpty, "Old item's subtitles must clear immediately")
        XCTAssertNil(store.selectedSubtitleTrack)
        XCTAssertFalse(store.selectSubtitleTrack(0), "Replaced item must reject stale selection")
        XCTAssertFalse(store.selectSubtitleTrack(nil))
        store.clear()
        XCTAssertTrue(store.subtitleTracks.isEmpty)
        XCTAssertTrue(store.player.appliesMediaSelectionCriteriaAutomatically)
    }

    func testPerTitleSubtitleSelectionAndOffRestoreWithoutPersistingURL() async throws {
        let mediaURL = "http://127.0.0.1:8766/master.m3u8"
        let key = "tv-next-native-subtitle-preferences-v1"
        XCTAssertFalse(store.selectSubtitleTrack(0))
        store.play(channel("Synthetic subtitles", url: mediaURL))
        try await waitUntil({ self.store.subtitleTracks.count == 1 }, timeout: 15)
        XCTAssertFalse(store.selectSubtitleTrack(-1))
        XCTAssertFalse(store.selectSubtitleTrack(16))
        XCTAssertNil(defaults.data(forKey: key))
        XCTAssertTrue(store.selectSubtitleTrack(0))
        let data = try XCTUnwrap(defaults.data(forKey: key))
        XCTAssertLessThanOrEqual(data.count, 64_000)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(mediaURL))
        let restored = MediaLibraryStore(defaults: defaults)
        restored.play(channel("Synthetic subtitles", url: mediaURL))
        try await waitUntil({ restored.subtitleTracks.count == 1 && restored.selectedSubtitleTrack == 0 }, timeout: 15)
        XCTAssertFalse(restored.player.appliesMediaSelectionCriteriaAutomatically)
        XCTAssertTrue(restored.canDisableEmbeddedSubtitles)
        XCTAssertTrue(restored.selectSubtitleTrack(nil))
        let off = try XCTUnwrap(defaults.data(forKey: key))
        let offObject = try XCTUnwrap(JSONSerialization.jsonObject(with: off) as? [String: Any])
        let offEntries = try XCTUnwrap(offObject["entries"] as? [[String: Any]])
        XCTAssertEqual(offEntries.last?["isOff"] as? Bool, true)
        let offRestored = MediaLibraryStore(defaults: defaults)
        offRestored.play(channel("Synthetic subtitles", url: mediaURL))
        try await waitUntil({ offRestored.subtitleTracks.count == 1 &&
                              !offRestored.player.appliesMediaSelectionCriteriaAutomatically }, timeout: 15)
        XCTAssertNil(offRestored.selectedSubtitleTrack)
        offRestored.playLocalFile(try fixture(), name: "fixture.mp4")
        XCTAssertTrue(offRestored.player.appliesMediaSelectionCriteriaAutomatically)
        XCTAssertFalse(offRestored.selectSubtitleTrack(nil))
        offRestored.clear()
        XCTAssertNil(defaults.data(forKey: key))
    }

    func testSubtitlePreferenceIdentityNeverTruncatesAmbiguousLongNames() {
        let sharedPrefix = String(repeating: "A", count: 80)
        let first = sharedPrefix + " - English"
        let second = sharedPrefix + " - Commentary"
        XCTAssertNotEqual(first, second)
        XCTAssertNil(MediaLibraryStore.persistableSubtitleDisplayName(first))
        XCTAssertNil(MediaLibraryStore.persistableSubtitleDisplayName(second))
        XCTAssertEqual(MediaLibraryStore.persistableSubtitleDisplayName(sharedPrefix), sharedPrefix)
        XCTAssertNil(MediaLibraryStore.persistableSubtitleDisplayName(""))
        XCTAssertNil(MediaLibraryStore.persistableSubtitleDisplayName(String(repeating: "x", count: 81)))
    }

    func testCorruptedOrUnmatchedSubtitlePreferencesDoNotOverrideSystemSelection() async throws {
        let key = "tv-next-native-subtitle-preferences-v1"
        let mediaURL = "http://127.0.0.1:8766/master.m3u8"
        defaults.set(Data("not-json".utf8), forKey: key)
        let corrupted = MediaLibraryStore(defaults: defaults)
        corrupted.play(channel("Synthetic subtitles", url: mediaURL))
        try await waitUntil({ corrupted.subtitleTracks.count == 1 }, timeout: 15)
        XCTAssertTrue(corrupted.player.appliesMediaSelectionCriteriaAutomatically)
        XCTAssertFalse(corrupted.selectSubtitleTrack(100))
        XCTAssertEqual(defaults.data(forKey: key), Data("not-json".utf8))

        let digest = SHA256.hash(data: Data(mediaURL.utf8)).map { String(format: "%02x", $0) }.joined()
        let missing = """
        {"version":1,"entries":[{"urlDigest":"\(digest)","displayName":"Absent subtitle",
        "languageTag":"zz","isOff":false}]}
        """
        defaults.set(Data(missing.utf8), forKey: key)
        let unmatched = MediaLibraryStore(defaults: defaults)
        unmatched.play(channel("Synthetic subtitles", url: mediaURL))
        try await waitUntil({ unmatched.subtitleTracks.count == 1 }, timeout: 15)
        XCTAssertTrue(unmatched.player.appliesMediaSelectionCriteriaAutomatically)
        unmatched.clear()
        XCTAssertNil(defaults.data(forKey: key))
    }

    func testPlaybackSpeedBoundsAndInvalidNumbers() {
        store.setPlaybackSpeed(1.5)
        store.setPlaybackSpeed(.nan)
        store.setPlaybackSpeed(.infinity)
        XCTAssertEqual(store.playbackSpeed, 1.5)
        store.setPlaybackSpeed(100)
        XCTAssertEqual(store.playbackSpeed, 2)
        store.setPlaybackSpeed(-1)
        XCTAssertEqual(store.playbackSpeed, 0.75)
    }

    func testLocalPlaybackAndFailureRecoveryNeverPersistFileURLs() async throws {
        let bad = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        try Data("not a video".utf8).write(to: bad)
        defer { try? FileManager.default.removeItem(at: bad) }
        store.playLocalFile(bad, name: "bad.mp4")
        try await waitUntil { self.store.playbackError != nil }
        store.playLocalFile(try fixture(), name: "fixture.mp4")
        try await waitUntil { self.store.player.currentItem?.status == .readyToPlay }
        XCTAssertNil(store.playbackError)
        XCTAssertTrue(store.recent.isEmpty)
        XCTAssertTrue(store.positions.isEmpty)
        XCTAssertNil(store.current)
        store.retryPlayback()
        try await waitUntil { self.store.player.currentItem?.status == .readyToPlay }
        XCTAssertNil(store.playbackError)
        XCTAssertFalse(String(decoding: defaults.data(forKey: "tv-next-library-v1") ?? Data(), as: UTF8.self).contains("file:"))
        store.clear()
        XCTAssertNil(store.player.currentItem)
        XCTAssertNil(store.playbackError)
    }

    func testFiniteVODResumeBackgroundSaveAndClear() async throws {
        // A same-device local HTTP fixture exercises the real URL path and AVPlayer clock.
        let source = channel(url: "http://127.0.0.1:8765/fixture.mp4")
        try store.restoreSnapshot(NativeLibrarySnapshot(version: 1, channels: [source], favorites: [], recent: [], positions: [source.url: 20]))
        store.play(source)
        try await waitUntil { self.store.player.currentTime().seconds >= 19 }
        store.suspendPlayback()
        XCTAssertEqual(store.player.rate, 0)
        XCTAssertGreaterThanOrEqual(store.positions[source.url] ?? 0, 19)
        let restored = MediaLibraryStore(defaults: defaults)
        XCTAssertGreaterThanOrEqual(restored.positions[source.url] ?? 0, 19)
        XCTAssertEqual(restored.recent.first?.url, source.url)
        store.clear()
        XCTAssertNil(defaults.data(forKey: "tv-next-library-v1"))
        XCTAssertTrue(store.channels.isEmpty)
        XCTAssertTrue(store.positions.isEmpty)
    }

    func testSwitchingItemsRejectsStaleResumeAndNearEndPosition() async throws {
        let source = channel(url: "http://127.0.0.1:8765/fixture.mp4")
        try store.restoreSnapshot(NativeLibrarySnapshot(version: 1, channels: [source], favorites: [], recent: [], positions: [source.url: 85]))
        store.play(source)
        store.playLocalFile(try fixture(), name: "local.mp4")
        try await waitUntil { self.store.player.currentItem?.status == .readyToPlay }
        XCTAssertLessThan(store.player.currentTime().seconds, 10)
        store.play(source)
        try await waitUntil { self.store.player.currentItem?.status == .readyToPlay }
        XCTAssertLessThan(store.player.currentTime().seconds, 10, "Near-end positions must not resume")
    }

    func testStagedFileValidationCopyAndCleanup() async throws {
        let original = try fixture()
        let staged = try await LocalMediaStager.stage(original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.path))
        XCTAssertNotEqual(staged, original)
        XCTAssertEqual(try Data(contentsOf: staged), try Data(contentsOf: original))
        LocalMediaStager.discard(original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path), "Do not delete files outside managed cache")
        LocalMediaStager.discard(staged)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        FileManager.default.createFile(atPath: empty.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: empty) }
        do { _ = try await LocalMediaStager.stage(empty); XCTFail("Accepted an empty file") }
        catch { XCTAssertTrue(error is LocalMediaError) }
        let handle = try FileHandle(forWritingTo: empty)
        try handle.truncate(atOffset: 2_147_483_649) // Sparse file; no multi-GiB allocation.
        try handle.close()
        do { _ = try await LocalMediaStager.stage(empty); XCTFail("Accepted an oversized file") }
        catch { XCTAssertTrue(error is LocalMediaError) }
        do { _ = try await LocalMediaStager.stage(empty.deletingPathExtension().appendingPathExtension("mkv")); XCTFail("Accepted unsupported format") }
        catch { XCTAssertTrue(error is LocalMediaError) }
    }
    func testRetryTargetsFailedRelaySelectionRatherThanPreviousMedia() async throws {
        var requests: [String] = []
        let relayStore = MediaLibraryStore(defaults: defaults, createRelay: { _, request in
            requests.append(request.url)
            throw URLError(.cannotConnectToHost)
        })
        defer { relayStore.clear() }
        let session = NativeHomeSession(token: "unit-fixture", user: NativeHomeUser(id: "u", username: "fixture"),
            device: NativeHomeDevice(id: "d", name: "fixture", createdAt: 0, expiresAt: Int64.max, current: true))
        relayStore.configureRelay(server: "http://127.0.0.1:8765", session: session)
        relayStore.playLocalFile(try fixture(), name: "previous.mp4")
        var target = channel("Needs headers")
        target.headers = ["Referer": "https://example.invalid/"]
        relayStore.play(target)
        try await waitUntil { relayStore.playbackError != nil }
        relayStore.retryPlayback()
        try await waitUntil { requests.count == 2 && relayStore.playbackError != nil }
        XCTAssertEqual(requests, [target.url, target.url])
    }

    func testSuspensionInvalidatesLateRelayCompletion() async throws {
        var pending: CheckedContinuation<NativeRelayResponse, Error>?
        var returned = false
        let relayStore = MediaLibraryStore(defaults: defaults, createRelay: { _, _ in
            let result: NativeRelayResponse = try await withCheckedThrowingContinuation { pending = $0 }
            returned = true
            return result
        })
        defer { relayStore.clear() }
        let session = NativeHomeSession(token: "unit-fixture", user: NativeHomeUser(id: "u", username: "fixture"),
            device: NativeHomeDevice(id: "d", name: "fixture", createdAt: 0, expiresAt: Int64.max, current: true))
        relayStore.configureRelay(server: "http://127.0.0.1:8765", session: session)
        var target = channel("Delayed relay")
        target.headers = ["Referer": "https://example.invalid/"]
        relayStore.play(target)
        try await waitUntil { pending != nil }
        relayStore.setBackgroundPlaybackEnabled(true)
        relayStore.setApplicationBackground(true)
        // Deliberately emulate a transport that finishes despite cancellation.
        pending?.resume(returning: NativeRelayResponse(path: "/api/v1/home/media/" + String(repeating: "a", count: 43) + "/0", expiresAt: Int64.max))
        pending = nil
        try await waitUntil { returned }
        // Drain the actor so the late completion has been processed.
        for _ in 0..<10 { await Task.yield() }
        XCTAssertNil(relayStore.current)
        XCTAssertNil(relayStore.player.currentItem)
        XCTAssertEqual(relayStore.player.rate, 0)
        XCTAssertTrue(relayStore.recent.isEmpty)
    }

    func testPictureInPictureBackgroundAndInterruptionPolicy() async throws {
        store.playLocalFile(try fixture(), name: "fixture.mp4")
        try await waitUntil { self.store.player.currentItem?.status == .readyToPlay && self.store.player.rate > 0 }
        let coordinator = NativePlayerView.Coordinator(library: store, onRestore: {})
        coordinator.playerViewControllerWillStartPictureInPicture(AVPlayerViewController())
        store.suspendPlayback()
        XCTAssertTrue(store.pictureInPictureActive)
        XCTAssertGreaterThan(store.player.rate, 0, "Explicit PiP must survive backgrounding")
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        try await waitUntil { self.store.player.rate == 0 }
        store.player.playImmediately(atRate: 1)
        store.setPictureInPictureActive(false, appIsBackground: true)
        XCTAssertEqual(store.player.rate, 0, "Stopping PiP in the background must pause")
        var restored = false
        let restoreCoordinator = NativePlayerView.Coordinator(library: store, onRestore: { restored = true })
        var completed = false
        restoreCoordinator.playerViewController(AVPlayerViewController(), restoreUserInterfaceForPictureInPictureStopWithCompletionHandler: { completed = $0 })
        XCTAssertTrue(restored)
        XCTAssertTrue(completed)
    }

    func testRejectedSelectionInvalidatesPreviousPendingRelay() async throws {
        var pending: CheckedContinuation<NativeRelayResponse, Error>?
        var returned = false
        let relayStore = MediaLibraryStore(defaults: defaults, createRelay: { _, _ in
            let result: NativeRelayResponse = try await withCheckedThrowingContinuation { pending = $0 }
            returned = true
            return result
        })
        defer { relayStore.clear() }
        let session = NativeHomeSession(token: "unit-fixture", user: NativeHomeUser(id: "u", username: "fixture"),
            device: NativeHomeDevice(id: "d", name: "fixture", createdAt: 0, expiresAt: Int64.max, current: true))
        relayStore.configureRelay(server: "http://127.0.0.1:8765", session: session)
        var first = channel("Pending")
        first.headers = ["Referer": "https://example.invalid/"]
        relayStore.play(first)
        try await waitUntil { pending != nil }
        var rejected = channel("Reload required", url: "https://example.invalid/second.mp4")
        rejected.headersRequired = true
        relayStore.play(rejected)
        pending?.resume(returning: NativeRelayResponse(path: "/api/v1/home/media/" + String(repeating: "a", count: 43) + "/0", expiresAt: Int64.max))
        pending = nil
        try await waitUntil { returned }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertNil(relayStore.player.currentItem)
        XCTAssertTrue(relayStore.recent.isEmpty)
        XCTAssertNotNil(relayStore.playbackError)
    }

    func testReplayCapabilityAndProviderTemplatesNeverPersist() throws {
        var original=channel("Replay")
        original.timeshift=NativeTimeshift(url:"https://example.invalid/seek?time={time}",start:1,window:1000)
        original.catchup=NativeCatchup(source:"?begin=${(b)timestamp}")
        original.replay=NativeReplaySession(path:"/api/v1/home/media/"+String(repeating:"a",count:43)+"/0",expiresAt:Int64.max,hls:true,time:1)
        XCTAssertTrue(store.importChannels([original]))
        let snapshot=store.syncedSnapshot().channels[0]
        XCTAssertNil(snapshot.timeshift);XCTAssertNil(snapshot.catchup);XCTAssertNil(snapshot.replay)
        let restored=MediaLibraryStore(defaults:defaults)
        defer { restored.clear() }
        XCTAssertNil(restored.channels[0].timeshift);XCTAssertNil(restored.channels[0].catchup)
        let encoded=String(data:try JSONEncoder().encode(original),encoding:.utf8)!
        XCTAssertFalse(encoded.contains("/api/v1/home/media/"))
    }

    func testReplayRetryRenewsTicketAndPreservesOriginalSelection() async throws {
        var calls: [NativeReplaySelection] = []
        let freshPath="/api/v1/home/media/"+String(repeating:"c",count:43)+"/0"
        let relayStore=MediaLibraryStore(defaults:defaults,resolveReplay:{ _,request in
            calls.append(NativeReplaySelection(time:request.time,stop:request.stop,timezone:request.timezone))
            return NativeReplaySession(path:freshPath,expiresAt:Int64.max,hls:false,time:request.time)
        })
        defer { relayStore.clear() }
        let session=NativeHomeSession(token:"unit-fixture",user:NativeHomeUser(id:"u",username:"fixture"),
            device:NativeHomeDevice(id:"d",name:"fixture",createdAt:0,expiresAt:Int64.max,current:true))
        relayStore.configureRelay(server:"http://127.0.0.1:8765",session:session)
        var target=channel("Replay")
        let selection=NativeReplaySelection(time:123456,stop:234567,timezone:"Asia/Hong_Kong")
        target.replaySelection=selection
        target.replay=NativeReplaySession(path:"/api/v1/home/media/"+String(repeating:"a",count:43)+"/0",
            expiresAt:Int64.max,hls:false,time:selection.time)
        relayStore.play(target)
        relayStore.retryPlayback()
        try await waitUntil { relayStore.current?.replay?.path == freshPath }
        XCTAssertEqual(calls,[selection])
        XCTAssertEqual(relayStore.current?.url,target.url)
        XCTAssertEqual(relayStore.recent.first?.url,target.url)
        XCTAssertNil(relayStore.syncedSnapshot().channels.first?.replay)
    }

    func testNativeProgrammeReplayOwnershipInvalidatesOlderSelections() {
        let coordinator=NativeReplayRequestCoordinator()
        let first=coordinator.begin()
        let second=coordinator.begin()
        XCTAssertFalse(coordinator.isCurrent(first))
        XCTAssertTrue(coordinator.isCurrent(second))
        coordinator.invalidate()
        XCTAssertFalse(coordinator.isCurrent(second))
    }

    func testReplayWithoutSelectionCannotReuseClosedTicket() {
        let session=NativeHomeSession(token:"unit-fixture",user:NativeHomeUser(id:"u",username:"fixture"),
            device:NativeHomeDevice(id:"d",name:"fixture",createdAt:0,expiresAt:Int64.max,current:true))
        store.configureRelay(server:"http://127.0.0.1:8765",session:session)
        var target=channel("Replay")
        target.replay=NativeReplaySession(path:"/api/v1/home/media/"+String(repeating:"a",count:43)+"/0",
            expiresAt:Int64.max,hls:false,time:1)
        store.play(target)
        store.retryPlayback()
        XCTAssertEqual(store.playbackError,"回放会话不可直接重试，请重新选择回放时间。")
    }

    func testInvalidReplayKeepsExistingPlayerAndHistory() throws {
        let original=channel("Live")
        store.play(original)
        let item=store.player.currentItem
        var replay=original
        replay.replay=NativeReplaySession(path:"https://attacker.invalid/",expiresAt:Int64.max,hls:false,time:1)
        store.play(replay)
        XCTAssertTrue(store.player.currentItem === item)
        XCTAssertEqual(store.current,original)
        XCTAssertEqual(store.recent.count,1)
        XCTAssertNotNil(store.playbackError)
    }

}
