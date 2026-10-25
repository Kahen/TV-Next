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
        menu.tap()
        app.buttons[name].tap()
    }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<8 {
            if element.isHittable { return }
            print("Reveal target \(element.identifier): exists=\(element.exists) frame=\(element.frame)")
            let frame = element.frame
            if element.exists && frame.maxY < app.windows.firstMatch.frame.minY + 100 {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
        }
        if !element.isHittable { print("Unreachable element: \(element.debugDescription)\n\(app.debugDescription)") }
        XCTAssertTrue(element.isHittable)
    }

    private func enter(_ element: XCUIElement, _ text: String) {
        reveal(element)
        element.tap()
        if let current = element.value as? String, !current.isEmpty {
            element.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
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
            app.buttons["删除本地媒体库"].tap()
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
        XCTAssertTrue(app.staticTexts["还没有收藏的频道。"].exists)
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
        reveal(fullscreen)
        fullscreen.tap()
        let close = app.buttons["exit-fullscreen"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(close.isHittable)
        close.tap()
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
