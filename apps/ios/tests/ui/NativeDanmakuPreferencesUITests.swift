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

        func expectValue(_ expected: String) {
            let toggle = app.switches["danmaku-enabled-toggle"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 10))
            let predicate = NSPredicate(format: "value == %@", expected)
            XCTAssertEqual(
                XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: toggle)], timeout: 10),
                .completed,
                "Native danmaku toggle did not reach expected value \(expected)"
            )
        }

        openDanmakuSettings()
        let toggle = app.switches["danmaku-enabled-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        if toggle.value as? String != "0" { toggle.tap() }
        expectValue("0")

        app.terminate()
        app.launch()
        openDanmakuSettings()
        expectValue("0")

        // Restore the default for other production UI tests in the same simulator.
        app.switches["danmaku-enabled-toggle"].tap()
        expectValue("1")
    }
}
