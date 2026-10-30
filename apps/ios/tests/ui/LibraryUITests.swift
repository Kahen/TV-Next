import UIKit
import XCTest

/// Exercises production views, persistence and navigation; no seeded library or test-only app routes.
@MainActor
final class LibraryUITests: XCTestCase {
    private var app: XCUIApplication!
    private var currentSection = "媒体库"

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
        // Do not synchronously terminate here: on slower iPad simulators
        // XCTest can fail an otherwise passing case if SpringBoard refuses
        // termination while the app is backgrounding. The next setUp()
        // calls launch(), which relaunches the target; explicit
        // terminate/relaunch assertions inside persistence tests remain.
        app = nil
    }

    private func jump(_ name: String) {
        if name == "媒体库" {
            // A dedicated production toolbar action avoids compact iPhone Menu
            // truncation; every test uses this path when clearing local state.
            let shortcut = app.buttons["library-navigation"]
            XCTAssertTrue(shortcut.waitForExistence(timeout: 5))
            shortcut.tap()
            currentSection = name
            return
        }
        let menu = app.buttons["section-navigation"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: menu)], timeout: 5), .completed)
        menu.tap()
        let destination = app.buttons[name]
        destination.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: destination)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed, "Navigation menu did not dismiss")
        currentSection = name
    }

    private func reveal(_ element: XCUIElement) {
        // XCTest can throw while evaluating hittability for a SwiftUI child
        // outside the viewport. Check existence and safe geometry first, also
        // inside waits; a hittable-only predicate bypasses that protection.
        func visibleViewport() -> CGRect {
            // AVKit may insert an empty auxiliary window ahead of the main
            // window. Using firstMatch made drag distances zero after playback.
            var bounds = app.frame
            if bounds.isEmpty || bounds.isInfinite {
                bounds = app.windows.allElementsBoundByIndex.map(\.frame)
                    .filter { !$0.isEmpty && !$0.isInfinite }
                    .max { $0.width * $0.height < $1.width * $1.height } ?? .zero
            }
            if bounds.isEmpty || bounds.isInfinite {
                // The test runner shares the simulator's UIKit screen. Keep a
                // nonzero point-space fallback if AX publishes no window frame.
                let screen = UIScreen.main.bounds
                let landscape = XCUIDevice.shared.orientation == .landscapeLeft || XCUIDevice.shared.orientation == .landscapeRight
                bounds = CGRect(x: 0, y: 0,
                    width: landscape ? max(screen.width, screen.height) : min(screen.width, screen.height),
                    height: landscape ? min(screen.width, screen.height) : max(screen.width, screen.height))
            }
            return bounds.insetBy(dx: 8, dy: 90)
        }
        func visible() -> Bool {
            guard element.exists else { return false }
            let frame = element.frame
            let viewport = visibleViewport()
            return !frame.isEmpty && !frame.isInfinite && viewport.contains(frame)
        }
        // A SwiftUI TextField may report an AX activation-point exception when
        // isHittable is queried during a scroll transition. Geometry checks
        // do not request an activation point; actual taps still exercise UI.
        let reachable = NSPredicate { _, _ in visible() }
        if XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: reachable, object: element)], timeout: 3) == .completed { return }
        var resetToSection = false
        for _ in 0..<12 {
            guard element.exists else {
                if !resetToSection { jump(currentSection); resetToSection = true }
                else { app.swipeUp() }
                continue
            }
            let frame = element.frame
            let viewport = visibleViewport()
            guard !viewport.isEmpty else { app.activate(); continue }
            if visible() { return }
            print("Reveal frame=\(frame), viewport=\(viewport)")
            // Short controlled drags avoid oscillating past a control when its
            // layout moves after keyboard dismissal or a validation message.
            let amount: CGFloat
            if !frame.isEmpty && frame.minY < viewport.minY {
                amount = min(viewport.minY - frame.minY + 30, viewport.height * 0.25)
            } else {
                amount = -min(max(30, frame.maxY - viewport.maxY + 30), viewport.height * 0.25)
            }
            let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            origin.press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: 0, dy: amount)))
        }
        let reached = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: reachable, object: element)], timeout: 2) == .completed
        XCTAssertTrue(reached, "Target was not visible and hittable after bounded scrolling")
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

    func testNativeNavigationMenuExposesSubscriptionCloudAndGuide() {
        let menu = app.buttons["section-navigation"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        for label in ["TVBox 订阅", "网盘文件", "直播节目表", "家庭服务器", "弹幕设置"] {
            XCTAssertTrue(app.buttons[label].exists, "Missing native navigation: \(label)")
        }
        app.buttons["TVBox 订阅"].tap()
        XCTAssertTrue(app.staticTexts["TVBox / FongMi 原版订阅"].waitForExistence(timeout: 5))
    }

    func testNativeWebDAVFormRejectsUnsafeURLWithoutNetworking() {
        jump("WebDAV 文件")
        let connect = app.buttons["webdav-connect"]
        reveal(connect)
        XCTAssertTrue(connect.exists)
        XCTAssertFalse(connect.isEnabled)
        enter(app.textFields["webdav-url"], "javascript:alert(1)")
        reveal(connect)
        connect.tap()
        XCTAssertTrue(app.staticTexts["webdav-error"].waitForExistence(timeout: 5))
        let disconnect = app.buttons["webdav-disconnect"]
        reveal(disconnect)
        disconnect.tap()
        XCTAssertFalse(app.staticTexts["webdav-error"].exists)
    }

    func testWebDAVFilterAndRefreshAreConnectionScoped() {
        jump("WebDAV 文件")
        let connect = app.buttons["webdav-connect"]
        reveal(connect)
        XCTAssertFalse(connect.isEnabled)
        XCTAssertFalse(app.buttons["webdav-refresh"].exists)
        XCTAssertFalse(app.textFields["webdav-filter"].exists)
        XCTAssertFalse(app.buttons["webdav-sort"].exists)
        enter(app.textFields["webdav-url"], "javascript:alert(1)")
        reveal(connect)
        connect.tap()
        XCTAssertTrue(app.staticTexts["webdav-error"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["webdav-refresh"].exists)
        reveal(app.buttons["webdav-disconnect"])
        app.buttons["webdav-disconnect"].tap()
        XCTAssertFalse(app.staticTexts["webdav-error"].exists)
    }

    func testWebDAVRefreshAndLocalFilterAgainstOwnedFixture() {
        jump("WebDAV 文件")
        enter(app.textFields["webdav-url"], "http://127.0.0.1:8767/dav/")
        let connect = app.buttons["webdav-connect"]
        reveal(connect)
        connect.tap()
        let owned = app.buttons["Owned.mp4"]
        let folder = app.buttons["Folder"]
        XCTAssertTrue(owned.waitForExistence(timeout: 15), "Localhost Depth:1 listing did not load")
        XCTAssertTrue(folder.exists)
        XCTAssertTrue(app.staticTexts["webdav-size-Owned.mp4"].waitForExistence(timeout: 5),
                      "Successful DAV:getcontentlength must appear beside the native file")
        XCTAssertFalse(app.staticTexts["webdav-size-Folder"].exists, "Directories must never display a file size")
        let sort = app.buttons["webdav-sort"]
        reveal(sort)
        XCTAssertTrue(sort.label.contains("升序"))
        sort.tap()
        XCTAssertTrue(sort.label.contains("降序"), "Native sort button must update its real state")
        let toggle = app.switches["webdav-media-only"]
        reveal(toggle)
        toggle.tap()
        XCTAssertTrue(owned.exists)
        XCTAssertTrue(folder.exists, "Media-only mode must retain navigable folders")
        enter(app.textFields["webdav-filter"], "owned")
        XCTAssertTrue(owned.exists, "Case-insensitive local search lost the matching file")
        XCTAssertFalse(folder.exists, "Search should narrow the visible listing")
        // Draft credentials for another server must not affect this connection.
        // The original anonymous HTTP fixture would reject newly applied Basic auth.
        enter(app.textFields["webdav-url"], "https://unconnected.example/dav/")
        enter(app.textFields["webdav-user"], "unconnected-account")
        let refresh = app.buttons["webdav-refresh"]
        reveal(refresh)
        refresh.tap()
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            refresh.exists && refresh.isEnabled
        }, object: refresh)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 15), .completed)
        XCTAssertFalse(app.staticTexts["webdav-error"].waitForExistence(timeout: 2),
                       "Editing an unconnected form applied credentials to the active server")
        XCTAssertTrue(owned.waitForExistence(timeout: 15))
        XCTAssertTrue(sort.label.contains("降序"), "Refresh must preserve the local sort selection")
        XCTAssertFalse(folder.exists, "Refreshing the same folder must preserve its local search")
        let disconnect = app.buttons["webdav-disconnect"]
        reveal(disconnect)
        disconnect.tap()
        XCTAssertFalse(app.textFields["webdav-filter"].exists)
        XCTAssertFalse(sort.exists)
        XCTAssertFalse(refresh.exists)
    }

    func testWebDAVBreadcrumbReturnsToRootUsingOwnedFixture() {
        jump("WebDAV 文件")
        enter(app.textFields["webdav-url"], "http://127.0.0.1:8767/dav/")
        let connect = app.buttons["webdav-connect"]
        reveal(connect)
        connect.tap()
        let folder = app.buttons["Folder"]
        XCTAssertTrue(folder.waitForExistence(timeout: 15))
        reveal(folder)
        folder.tap()
        let rootShortcut = app.buttons["webdav-root"]
        XCTAssertTrue(rootShortcut.waitForExistence(timeout: 15), "Nested WebDAV folder has no root breadcrumb")
        reveal(rootShortcut)
        rootShortcut.tap()
        XCTAssertTrue(app.buttons["Owned.mp4"].waitForExistence(timeout: 15), "Root listing did not return")
        XCTAssertFalse(app.buttons["webdav-root"].exists, "Root must not show a redundant ancestor shortcut")
    }

    func testInlineSeekControlsArePresentAndDisabledWithoutMedia() {
        jump("播放器")
        let back = app.buttons["seek-back-15"]
        let forward = app.buttons["seek-forward-15"]
        reveal(back)
        XCTAssertTrue(back.exists)
        XCTAssertTrue(forward.exists)
        XCTAssertFalse(back.isEnabled)
        XCTAssertFalse(forward.isEnabled)
    }

    func testPlaybackDiagnosticsCanExpandAndRefreshWithoutMedia() {
        jump("播放器")
        let diagnostics = app.buttons["playback-diagnostics"]
        reveal(diagnostics)
        diagnostics.tap()
        let state = app.staticTexts["diagnostics-state"]
        XCTAssertTrue(state.waitForExistence(timeout: 5))
        XCTAssertTrue(state.label.contains("尚未选择媒体"))
        let refresh = app.buttons["diagnostics-refresh"]
        reveal(refresh)
        refresh.tap()
        XCTAssertTrue(state.label.contains("尚未选择媒体"))
    }

    func testOfflineDownloadSurvivesRelaunchAndCanBePlayedAndDeleted() {
        jump("离线媒体")
        let previous = app.buttons["offline-delete-Owned Offline"]
        if previous.exists {
            reveal(previous)
            previous.tap()
            XCTAssertTrue(app.alerts["删除离线媒体？"].waitForExistence(timeout: 5))
            app.alerts.buttons["删除离线文件"].tap()
            XCTAssertFalse(previous.exists)
        }
        enter(app.textFields["offline-url"], "http://127.0.0.1:8765/fixture.mp4")
        enter(app.textFields["offline-name"], "Owned Offline")
        XCTAssertTrue(app.staticTexts["offline-storage-usage"].exists)
        let download = app.buttons["offline-download"]
        reveal(download)
        download.tap()
        let play = app.buttons["offline-play-Owned Offline"]
        XCTAssertTrue(play.waitForExistence(timeout: 30))
        app.terminate()
        app.launch()
        jump("离线媒体")
        reveal(play)
        play.tap()
        jump("播放器")
        let current = app.staticTexts["current-media"]
        reveal(current)
        XCTAssertTrue(current.label.contains("Owned Offline"))
        jump("离线媒体")
        let remove = app.buttons["offline-delete-Owned Offline"]
        reveal(remove)
        remove.tap()
        let confirmation = app.alerts["删除离线媒体？"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["取消"].tap()
        XCTAssertTrue(play.exists, "Cancelling deletion must retain the offline file")
        jump("播放器")
        reveal(current)
        XCTAssertTrue(current.label.contains("Owned Offline"), "Cancellation must not stop active playback")
        jump("离线媒体")
        reveal(remove)
        remove.tap()
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["删除离线文件"].tap()
        XCTAssertFalse(play.exists, "Confirmed deletion must remove the offline catalog entry")
        jump("播放器")
        XCTAssertTrue(app.staticTexts["current-media"].label.contains("尚未选择媒体"), "Confirmed deletion must release the active local player item")
    }

    func testManualIntroOutroControlsDoNotMarkWithoutMedia() {
        jump("播放器")
        let intro = app.buttons["mark-intro-end"]
        let outro = app.buttons["mark-outro-start"]
        reveal(intro)
        XCTAssertTrue(intro.exists)
        XCTAssertTrue(outro.exists)
        XCTAssertFalse(intro.isEnabled)
        XCTAssertFalse(outro.isEnabled)
        XCTAssertFalse(app.buttons["skip-marked-intro"].exists)
        XCTAssertFalse(app.buttons["skip-marked-outro"].exists)
    }

    func testBackgroundAudioTogglePersistsAcrossRelaunch() {
        jump("播放器")
        let toggle=app.switches["background-playback-toggle"]
        reveal(toggle)
        func expectValue(_ value: String) {
            let expected=XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == %@",value),object:toggle)
            XCTAssertEqual(XCTWaiter.wait(for:[expected],timeout:5),.completed)
        }
        if toggle.value as? String == "1" { toggle.tap() }
        expectValue("0")
        toggle.tap()
        expectValue("1")
        app.terminate();app.launch();jump("播放器")
        reveal(toggle)
        expectValue("1")
        toggle.tap()
        expectValue("0")
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
        let forward = app.buttons["seek-forward-15"]
        reveal(forward)
        XCTAssertTrue(forward.isEnabled, "A selected player item exposes manual seek controls")
        let fullscreen = app.buttons["enter-fullscreen"]
        reveal(fullscreen)
        fullscreen.tap()
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

    func testManualDLNARejectsUnsafeRendererWithoutNetworking() {
        jump("DLNA 投屏")
        let cast = app.buttons["dlna-cast"]
        XCTAssertFalse(cast.isEnabled)
        XCTAssertFalse(app.buttons["dlna-pause"].isEnabled)
        XCTAssertFalse(app.buttons["dlna-query-state"].isEnabled)
        enter(app.textFields["dlna-renderer-url"], "http://8.8.8.8:1400/upnp/control")
        enter(app.textFields["dlna-media-url"], "https://media.example/owned.mp4?a=1&b=2")
        reveal(cast)
        XCTAssertFalse(cast.isEnabled, "Public WAN control endpoints must not be contacted")
        XCTAssertFalse(app.buttons["dlna-query-state"].isEnabled)
        XCTAssertFalse(app.staticTexts["dlna-status"].exists)
    }

    func testManualDLNACastPauseStopAgainstOwnedLoopbackFixture() {
        jump("DLNA 投屏")
        enter(app.textFields["dlna-renderer-url"], "http://127.0.0.1:8768/upnp/control/AVTransport1")
        enter(app.textFields["dlna-media-url"], "https://media.example/owned.mp4?a=1&b=2")
        let cast = app.buttons["dlna-cast"]
        reveal(cast)
        XCTAssertTrue(cast.isEnabled)
        cast.tap()
        let status = app.staticTexts["dlna-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 15), "Owned SOAP SetURI + Play did not complete")
        XCTAssertEqual(status.label, "投屏已开始")
        XCTAssertFalse(app.staticTexts["dlna-error"].exists)
        let query = app.buttons["dlna-query-state"]
        reveal(query)
        XCTAssertTrue(query.isEnabled)
        query.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "设备状态：正在播放"), object: status)], timeout: 15), .completed)
        let pause = app.buttons["dlna-pause"]
        reveal(pause)
        XCTAssertTrue(pause.isEnabled)
        pause.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "已发送暂停命令"), object: status)], timeout: 15), .completed)
        reveal(query)
        query.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "设备状态：已暂停"), object: status)], timeout: 15), .completed)
        let stop = app.buttons["dlna-stop"]
        reveal(stop)
        stop.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "已发送停止命令"), object: status)], timeout: 15), .completed)
        XCTAssertFalse(stop.isEnabled)
        reveal(query)
        query.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "设备状态：已停止"), object: status)], timeout: 15), .completed)
    }
}
