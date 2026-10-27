import XCTest

/// Exercises production views, persistence and navigation; no seeded library or test-only app routes.
@MainActor
final class LibraryUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        // Exercise large Dynamic Type rather than assuming default text fits.
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
        app.launch()
        clearLibraryIfNeeded()
    }

    override func tearDown() async throws {
        XCUIDevice.shared.orientation = .portrait
        app.terminate()
    }

    private func jump(_ name: String) {
        let menu = app.buttons["section-navigation"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: menu)], timeout: 5), .completed)
        menu.tap()
        app.buttons[name].tap()
    }

    private func reveal(_ element: XCUIElement) {
        // Offscreen SwiftUI elements can report an invalid activation point on iPhone.
        // Check visible geometry before asking XCTest for hittability; keep failing if
        // scrolling cannot actually reveal a tappable production control.
        let window = app.windows.firstMatch.frame
        for _ in 0..<12 {
            let frame = element.frame
            let intersection = frame.intersection(window)
            if element.exists && intersection.width >= 20 && intersection.height >= 20 {
                if element.isHittable { return }
            }
            print("Reveal target \(element.identifier): exists=\(element.exists) frame=\(frame)")
            if frame.width > 0 && frame.maxY < window.minY + 100 {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
        }
        print("Unreachable element: \(element.debugDescription)\n\(app.debugDescription)")
        XCTFail("Could not reveal a hittable \(element.identifier) after scrolling")
    }

    /// Tap the actual visible production control even when XCTest incorrectly reports
    /// a non-hittable SwiftUI button on iPad. The resulting fullscreen cover is asserted
    /// by the caller; a blocked/disabled control must still fail the UI test.
    private func tapVisible(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(element.isEnabled)
        let window = app.windows.firstMatch
        let viewport = window.frame.insetBy(dx: 0, dy: 80)
        for _ in 0..<12 {
            let frame = element.frame
            let visible = frame.intersection(viewport)
            if visible.width >= 20 && visible.height >= 20 {
                if element.isHittable {
                    element.tap()
                } else {
                    print("Coordinate-tapping visible but non-hittable control: \(element.identifier), frame=\(frame)")
                    let origin = window.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
                    origin.withOffset(CGVector(dx: visible.midX - window.frame.minX,
                                               dy: visible.midY - window.frame.minY)).tap()
                }
                return
            }
            if frame.maxY < viewport.minY { app.swipeDown() } else { app.swipeUp() }
        }
        XCTFail("Could not reveal visible control \(element.identifier)")
    }

    private func enter(_ element: XCUIElement, _ text: String) {
        let clear = app.buttons["clear-" + element.identifier]
        if clear.exists && clear.isEnabled { reveal(clear); clear.tap() }
        reveal(element)
        element.tap()
        element.typeText(text)
        let done = app.buttons["收起键盘"]
        if done.exists { done.tap() }
    }

    private func clearLibraryIfNeeded() {
        jump("媒体库")
        let clear = app.buttons["clear-library"]
        if clear.exists {
            reveal(clear)
            clear.tap()
            app.alerts.buttons["删除本地媒体库"].tap()
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.alerts.firstMatch)], timeout: 5), .completed)
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: clear)], timeout: 5), .completed)
        }
    }

    private func importPlaylist(_ text: String) {
        jump("导入播放列表")
        enter(app.textViews["playlist-input"], text)
        let button = app.buttons["import-playlist"]
        reveal(button)
        button.tap()
    }

    private func chooseCollection(_ name: String) {
        let picker = app.buttons["library-collection"]
        reveal(picker)
        picker.tap()
        app.buttons[name].tap()
    }

    func testImportFavoritesSearchHistoryRelaunchAndInvalidImportRecovery() {
        importPlaylist("#EXTM3U\n#EXTINF:-1 group-title=\"Owned\",Fixture MP4\nhttp://127.0.0.1:8765/fixture.mp4\n#EXTINF:-1,Second\nhttp://127.0.0.1:8765/fixture.m3u8")
        jump("媒体库")
        let channel = app.buttons["channel-Fixture MP4"]
        reveal(channel)
        app.buttons["favorite-Fixture MP4"].tap()
        chooseCollection("收藏")
        XCTAssertTrue(channel.exists)
        enter(app.textFields["library-search"], "missing")
        XCTAssertTrue(app.staticTexts["没有匹配的频道，请调整搜索。"].exists)
        enter(app.textFields["library-search"], "Fixture")
        reveal(channel)
        channel.tap()
        chooseCollection("最近播放")
        XCTAssertTrue(channel.exists)
        app.terminate()
        app.launch()
        jump("媒体库")
        chooseCollection("收藏")
        reveal(channel)
        XCTAssertEqual(app.buttons["favorite-Fixture MP4"].label, "取消收藏 Fixture MP4")
        importPlaylist("#EXTM3U\nfile:///not-allowed.mp4")
        XCTAssertTrue(app.staticTexts["import-error"].waitForExistence(timeout: 5))
        jump("媒体库")
        reveal(channel)
        XCTAssertTrue(channel.exists, "Invalid import erased the existing library")
        clearLibraryIfNeeded()
        app.terminate()
        app.launch()
        jump("媒体库")
        XCTAssertFalse(channel.exists)
    }

    func testPlaybackErrorRetryFullscreenRotationAndBackgroundReturn() {
        jump("快速播放")
        enter(app.textFields["manual-url"], "file:///not-allowed.mp4")
        reveal(app.buttons["play-url"])
        app.buttons["play-url"].tap()
        XCTAssertTrue(app.staticTexts["quick-play-error"].exists)
        enter(app.textFields["manual-url"], "http://127.0.0.1:8765/missing.mp4")
        reveal(app.buttons["play-url"])
        app.buttons["play-url"].tap()
        jump("播放器")
        let error = app.staticTexts["playback-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 20))
        reveal(app.buttons["retry-playback"])
        app.buttons["retry-playback"].tap()
        XCTAssertTrue(error.waitForExistence(timeout: 20))
        jump("快速播放")
        enter(app.textFields["manual-url"], "http://127.0.0.1:8765/fixture.mp4")
        reveal(app.buttons["play-url"])
        app.buttons["play-url"].tap()
        jump("播放器")
        XCTAssertFalse(error.exists)
        let fullscreen = app.buttons["enter-fullscreen"]
        tapVisible(fullscreen)
        let close = app.buttons["exit-fullscreen"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let hittable = NSPredicate(format: "hittable == true")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: hittable, object: close)], timeout: 5), .completed)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: hittable, object: close)], timeout: 5), .completed, close.debugDescription)
        close.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: close)], timeout: 5), .completed)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["section-navigation"].waitForExistence(timeout: 5))
        jump("播放器")
        XCTAssertTrue(app.staticTexts["current-media"].label.contains("自定义播放地址"))
    }

    func testJSONPreviewAndMalformedInputRecovery() {
        jump("JSON 配置")
        enter(app.textViews["config-input"], "{invalid")
        reveal(app.buttons["inspect-config"])
        app.buttons["inspect-config"].tap()
        XCTAssertTrue(app.staticTexts["config-error"].exists)
        enter(app.textViews["config-input"], "{\"sites\":[{\"key\":\"owned\",\"name\":\"Owned Fixture\",\"type\":1,\"api\":\"https://example.invalid/api\"}]}")
        reveal(app.buttons["inspect-config"])
        app.buttons["inspect-config"].tap()
        XCTAssertFalse(app.staticTexts["config-error"].exists)
        XCTAssertTrue(app.staticTexts["Owned Fixture"].exists)
    }
}
