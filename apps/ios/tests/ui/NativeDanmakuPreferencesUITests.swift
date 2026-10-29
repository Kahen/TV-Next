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

        func expectValue(_ expected: String) {
            let toggle = visibleToggle()
            let predicate = NSPredicate(format: "value == %@", expected)
            XCTAssertEqual(
                XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: toggle)], timeout: 10),
                .completed,
                "Native danmaku toggle did not reach expected value \(expected)"
            )
        }

        openDanmakuSettings()
        let toggle = visibleToggle()
        if toggle.value as? String != "0" { toggle.tap() }
        expectValue("0")

        app.terminate()
        app.launch()
        openDanmakuSettings()
        expectValue("0")

        // Restore the default for other production UI tests in the same simulator.
        visibleToggle().tap()
        expectValue("1")
    }
}
