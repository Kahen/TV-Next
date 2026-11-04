import Foundation
import XCTest
@testable import TVNext

final class NativeDanmakuOptionsTests: XCTestCase {
    private func isolatedDefaults() -> (UserDefaults, String) {
        let name = "dev.tvnext.danmaku.test.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    func testRoundTripAllPresentationOptionsWithoutMediaPayloads() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        var options = DanmakuOptions()
        options.enabled = false
        options.opacity = 0.4
        options.fontSize = 30
        options.area = 0.25
        options.duration = 12
        options.offset = -45
        options.blocked = "spoiler,剧透"
        XCTAssertTrue(DanmakuOptionsStore.save(options, to: defaults))
        XCTAssertEqual(DanmakuOptionsStore.load(from: defaults), options)
        let raw = String(decoding: defaults.data(forKey: DanmakuOptionsStore.key)!, as: UTF8.self)
        XCTAssertFalse(raw.contains("http://"))
        XCTAssertFalse(raw.contains("Authorization"))
        XCTAssertFalse(raw.contains("password"))
    }

    func testInvalidValuesNeverOverwriteLastGoodSnapshot() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        var options = DanmakuOptions()
        options.offset = 20
        XCTAssertTrue(DanmakuOptionsStore.save(options, to: defaults))
        for invalid in [Double.nan, Double.infinity, -1, 1.1] {
            var bad = options
            bad.opacity = invalid
            XCTAssertFalse(DanmakuOptionsStore.save(bad, to: defaults))
            XCTAssertEqual(DanmakuOptionsStore.load(from: defaults), options)
        }
        var bad = options
        bad.blocked = String(repeating: "剧", count: 1_400)
        XCTAssertFalse(DanmakuOptionsStore.save(bad, to: defaults))
        XCTAssertEqual(DanmakuOptionsStore.load(from: defaults), options)
    }

    func testCorruptMissingAndOversizedSnapshotsFallbackToDefaults() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        for data in [Data("{".utf8), Data("{\"enabled\":true}".utf8),
                     Data(repeating: 65, count: 8_193)] {
            defaults.set(data, forKey: DanmakuOptionsStore.key)
            XCTAssertEqual(DanmakuOptionsStore.load(from: defaults), DanmakuOptions())
        }
        var invalid = DanmakuOptions()
        invalid.duration = 100
        defaults.set(try! JSONEncoder().encode(invalid), forKey: DanmakuOptionsStore.key)
        XCTAssertEqual(DanmakuOptionsStore.load(from: defaults), DanmakuOptions())
    }

    func testBlockedWordsAreTruncatedOnScalarBoundary() {
        let long = String(repeating: "剧", count: 2_000)
        let bounded = DanmakuOptionsStore.boundedBlocked(long)
        XCTAssertEqual(bounded.utf8.count, 4_095)
        XCTAssertFalse(bounded.contains("�"))
        var options = DanmakuOptions()
        options.blocked = bounded
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertTrue(DanmakuOptionsStore.save(options, to: defaults))
        XCTAssertEqual(DanmakuOptionsStore.load(from: defaults).blocked, bounded)
    }

    func testClearAndSuiteIsolation() {
        let (first, firstName) = isolatedDefaults()
        let (second, secondName) = isolatedDefaults()
        defer {
            first.removePersistentDomain(forName: firstName)
            second.removePersistentDomain(forName: secondName)
        }
        var options = DanmakuOptions()
        options.enabled = false
        XCTAssertTrue(DanmakuOptionsStore.save(options, to: first))
        XCTAssertEqual(DanmakuOptionsStore.load(from: second), DanmakuOptions())
        DanmakuOptionsStore.clear(from: first)
        XCTAssertNil(first.data(forKey: DanmakuOptionsStore.key))
        XCTAssertEqual(DanmakuOptionsStore.load(from: first), DanmakuOptions())
    }
}
