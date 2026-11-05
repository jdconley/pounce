import XCTest

/// The age screen before pick-a-cat (spec §14.1). Declared Age Range is stubbed in Debug with
/// `-age-range <kitten|teen|adult|declined|unavailable>`; no server is needed.
@MainActor
final class AgeGateTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func app(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = Live.arguments() + ["-uitest-reset"] + extra
        app.launchEnvironment["POUNCE_API_BASE_URL"] = Live.baseURL
        return app
    }

    private func type(_ app: XCUIApplication, _ year: String) {
        for digit in year { el(app, "age.key.\(digit)").tap() }
    }

    func testDeclinedShowsKeypadThenPickCat() {
        let app = app(["-age-range", "declined"])
        app.launch()
        XCTAssertTrue(el(app, "age.confirm").waitForExistence(timeout: Live.t(10)), "no age keypad")
        // No default and no hint: every tile starts empty.
        for i in 0..<4 { XCTAssertEqual(value(el(app, "age.tile.\(i)")) ?? "", "", "tile \(i) not empty") }
        type(app, "1990")
        el(app, "age.confirm").tap()
        XCTAssertTrue(el(app, "screen-pickCat").waitForExistence(timeout: Live.t(10)), "no pick-a-cat")
        XCTAssertTrue(el(app, "pickcat.name").exists, "an adult types a name")
    }

    func testKittenGetsDiceOnly() {
        let app = app(["-age-range", "unavailable"])
        app.launch()
        XCTAssertTrue(el(app, "age.confirm").waitForExistence(timeout: Live.t(10)), "no age keypad")
        type(app, "2016")
        el(app, "age.confirm").tap()
        XCTAssertTrue(el(app, "screen-pickCat").waitForExistence(timeout: Live.t(10)), "no pick-a-cat")
        XCTAssertTrue(el(app, "pickcat.dice").exists)
        XCTAssertFalse(app.textFields["pickcat.name"].exists, "a kitten must not type a name")
        let shown = el(app, "pickcat.generatedName")
        XCTAssertTrue(shown.exists)
        let before = label(shown)
        el(app, "pickcat.dice").tap()
        XCTAssertTrue(until(3) { self.label(shown) != before }, "the dice rolls a new name")
        el(app, "pickcat.confirm").tap()
        XCTAssertTrue(el(app, "home.newGame").waitForExistence(timeout: Live.t(10)), "no Home")
    }

    func testSharedRangeSkipsKeypad() {
        let app = app(["-age-range", "teen"])
        app.launch()
        XCTAssertTrue(el(app, "screen-pickCat").waitForExistence(timeout: Live.t(10)), "no pick-a-cat")
        XCTAssertFalse(el(app, "age.confirm").exists)
        XCTAssertTrue(el(app, "pickcat.name").exists)
    }

    func testBadYearShakes() {
        let app = app(["-age-range", "declined"])
        app.launch()
        XCTAssertTrue(el(app, "age.confirm").waitForExistence(timeout: Live.t(10)), "no age keypad")
        type(app, "2030")
        el(app, "age.confirm").tap()
        Thread.sleep(forTimeInterval: Live.pace(1))
        XCTAssertTrue(el(app, "screen-age").exists, "a year in the future is not taken")
        XCTAssertFalse(el(app, "screen-pickCat").exists)
        type(app, "")
        el(app, "age.confirm").tap()
        XCTAssertTrue(el(app, "screen-age").exists, "an empty keypad is not taken")
    }

    func testKeypadCannotBeRetried() {
        let service = "com.conleychaos.play.age.uitest-\(UUID().uuidString)"
        let first = app(["-age-range", "declined", "-uitest-age-service", service])
        first.launch()
        XCTAssertTrue(el(first, "age.confirm").waitForExistence(timeout: Live.t(10)), "no age keypad")
        type(first, "2001")
        el(first, "age.confirm").tap()
        XCTAssertTrue(el(first, "screen-pickCat").waitForExistence(timeout: Live.t(10)), "no pick-a-cat")
        first.terminate()

        // A fresh launch (fresh files, same Keychain): the answer stands and the keypad is gone.
        let second = app(["-age-range", "declined", "-uitest-age-service", service])
        second.launch()
        XCTAssertTrue(el(second, "screen-pickCat").waitForExistence(timeout: Live.t(10)), "no pick-a-cat")
        XCTAssertFalse(el(second, "age.confirm").exists, "the keypad came back")
    }
}
