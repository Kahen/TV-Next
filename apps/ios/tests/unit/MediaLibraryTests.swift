import XCTest
import AVFoundation
import AVKit
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
        relayStore.suspendPlayback()
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

}
