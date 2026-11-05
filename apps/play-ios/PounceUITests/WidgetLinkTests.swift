import XCTest

/// Widget taps (spec §11.1): `pounce-widget://` links WidgetKit hands to the app, delivered here
/// at launch with `-open-widget-link` over the demo streaks (`DemoFixtures.streaks()`).
@MainActor
final class WidgetLinkTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ link: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = Live.arguments() + ["-uitest-reset", "-seed-people", "-demo-streaks", "-open-widget-link", link]
        app.launchEnvironment["POUNCE_API_BASE_URL"] = Live.baseURL
        app.launch()
        return app
    }

    func testUsLinkOpensPair() {
        let app = launch("pounce-widget://us?pair=pr_demoKikiAAAAAAAAAAAAAA")
        XCTAssertTrue(el(app, "screen-us").waitForExistence(timeout: Live.t(10)), "no Us screen")
        XCTAssertTrue(until(5) { self.label(self.el(app, "us.count")) == "9" }, "not on Kiki's streak")
        XCTAssertTrue(el(app, "us.pair.1").isSelected)
    }

    func testUsLinkWithoutPairOpensTopPair() {
        let app = launch("pounce-widget://us")
        XCTAssertTrue(el(app, "screen-us").waitForExistence(timeout: Live.t(10)), "no Us screen")
        XCTAssertTrue(until(5) { self.label(self.el(app, "us.count")) == "128" })
    }

    func testTableLinkLeavesHome() {
        let app = launch("pounce-widget://table/GH2VD")
        XCTAssertTrue(until(10) { !self.el(app, "screen-home").exists }, "still on Home")
        XCTAssertFalse(el(app, "screen-us").exists)
    }

    func testAppLinkStaysHome() {
        let app = launch("pounce-widget://app")
        XCTAssertTrue(el(app, "screen-home").waitForExistence(timeout: Live.t(10)))
    }
}
