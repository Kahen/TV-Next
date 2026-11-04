import XCTest

/// Production SwiftUI persistence check; no test-only routes or seeded preferences.
@MainActor
final class NativeDanmakuPreferencesUITests: XCTestCase {
    func testDisplayToggleSurvivesRealAppRelaunch() {
        let app = XCUIApplication()
        app.launch()

        func openDanmakuSettings() {
            let menu = app.buttons["section-navigation"]
            XCTAssertTrue(menu.waitForExistence(timeout: 15))
            menu.tap()
            let destination = app.buttons["弹幕设置"]
            XCTAssertTrue(destination.waitForExistence(timeout: 10))
            destination.tap()
        }

        // Exercise a real, accessible SwiftUI action instead of guessing the
        // tappable thumb coordinate of a platform-dependent switch row.
        func tapEnabledAction() {
            let action = app.buttons["danmaku-enabled-action"]
            XCTAssertTrue(action.waitForExistence(timeout: 10))
            action.tap()
        }

        func expectEnabled(_ enabled: Bool) {
            let status = app.staticTexts["danmaku-enabled-status"]
            XCTAssertTrue(status.waitForExistence(timeout: 10))
            let expected = enabled ? "弹幕已开启" : "弹幕已关闭"
            let predicate = NSPredicate(format: "label == %@", expected)
            XCTAssertEqual(
                XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: status)], timeout: 10),
                .completed,
                "Native danmaku UI state did not become \(expected); observed \(status.label)"
            )
        }

        openDanmakuSettings()
        let status = app.staticTexts["danmaku-enabled-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        // Establish the known enabled baseline even if another test left a
        // device-local preference behind, then prove a real write to disabled.
        if status.label != "弹幕已开启" { tapEnabledAction() }
        expectEnabled(true)
        tapEnabledAction()
        expectEnabled(false)

        app.terminate()
        app.launch()
        openDanmakuSettings()
        expectEnabled(false)

        // Restore the default for other production UI tests in the same simulator.
        tapEnabledAction()
        expectEnabled(true)
    }
}
