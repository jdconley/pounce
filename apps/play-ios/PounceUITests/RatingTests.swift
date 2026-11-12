import XCTest

/// The gear's "Rate Pounce" row (the App Store's review page): on an adult's device only. The
/// automatic rating ask never runs under a UI test (`RatingPrompt.isStaged`); its rules are unit
/// tested in PounceKit (`RatingPromptTests`). No server is needed.
@MainActor
final class RatingTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Home with the gear sheet open, on a device whose owner is in `band`.
    private func gear(band: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = Live.arguments() + ["-uitest-reset", "-seed-people", "-age-band", band, "-show-gear"]
        app.launchEnvironment["POUNCE_API_BASE_URL"] = Live.baseURL
        app.launch()
        XCTAssertTrue(el(app, "sheet-gear").waitForExistence(timeout: Live.t(15)), "no gear sheet for \(band)")
        XCTAssertTrue(el(app, "settings.rules").waitForExistence(timeout: Live.t(5)), "no How to play for \(band)")
        return app
    }

    func testAnAdultCanRatePounce() {
        let app = gear(band: "adult")
        let rate = el(app, "gear.rate")
        XCTAssertTrue(rate.waitForExistence(timeout: Live.t(5)), "an adult has no Rate Pounce row")
        XCTAssertEqual(label(rate), "Rate Pounce")
        for _ in 0..<4 where !rate.isHittable { el(app, "sheet-gear").swipeUp() }
        XCTAssertTrue(rate.isHittable, "the Rate Pounce row can't be reached")
        screenshot(app, "gear-rate")
    }

    func testATeenAndAKittenAreNeverAskedToRate() {
        for band in ["teen", "kitten"] {
            let app = gear(band: band)
            XCTAssertFalse(el(app, "gear.rate").exists, "a \(band) has a Rate Pounce row")
            app.terminate()
        }
    }
}
