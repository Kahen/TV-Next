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

        func visibleToggle() -> XCUIElement {
            let toggle = app.switches["danmaku-enabled-toggle"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 10))
            for _ in 0..<12 {
                // Avoid querying offscreen SwiftUI hittability directly: XCTest
                // may throw while resolving an accessibility frame outside the viewport.
                let frame = toggle.frame
                let viewport = app.frame.insetBy(dx: 8, dy: 60)
                if !frame.isEmpty && !viewport.isEmpty &&
                    viewport.contains(frame) && toggle.isHittable { return toggle }
                app.swipeUp()
            }
            XCTFail("Native danmaku control was not reachable after bounded scrolling")
            return toggle
        }

        // Assert the actual SwiftUI model state via visible feedback, not the
        // platform/locale-dependent XCUIElement.value representation of a switch.
        func tapToggle(_ toggle: XCUIElement) {
            // SwiftUI may expose the entire label row as the Switch frame. A
            // center tap can hit static label space without changing the value.
            // Target the trailing switch thumb instead of the row midpoint.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
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
        let toggle = visibleToggle()
        let status = app.staticTexts["danmaku-enabled-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        if status.label != "弹幕已关闭" { tapToggle(toggle) }
        expectEnabled(false)

        app.terminate()
        app.launch()
        openDanmakuSettings()
        expectEnabled(false)

        // Restore the default for other production UI tests in the same simulator.
        tapToggle(visibleToggle())
        expectEnabled(true)
    }
}
