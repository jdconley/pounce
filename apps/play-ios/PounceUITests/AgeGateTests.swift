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
        // The question is in words, for sight and VoiceOver.
        XCTAssertTrue(el(app, "age.question").exists, "no question on the age screen")
        type(app, "1990")
        el(app, "age.confirm").tap()
        // The year is said back before it is kept.
        XCTAssertTrue(el(app, "age.confirmYear").waitForExistence(timeout: Live.t(5)), "no confirm step")
        XCTAssertTrue((label(el(app, "age.confirmYear")) ?? "").contains("1990"), "the confirm step doesn't say the year")
        el(app, "age.yes").tap()
        XCTAssertTrue(el(app, "screen-pickCat").waitForExistence(timeout: Live.t(10)), "no pick-a-cat")
        XCTAssertTrue(el(app, "pickcat.name").exists, "an adult types a name")
    }

    func testKittenGetsDiceOnly() {
        let app = app(["-age-range", "unavailable"])
        app.launch()
        XCTAssertTrue(el(app, "age.confirm").waitForExistence(timeout: Live.t(10)), "no age keypad")
        type(app, "2016")
        el(app, "age.confirm").tap()
        el(app, "age.yes").tap()
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
        el(first, "age.yes").tap()
        XCTAssertTrue(el(first, "screen-pickCat").waitForExistence(timeout: Live.t(10)), "no pick-a-cat")
        first.terminate()

        // A fresh launch (fresh files, same Keychain): the answer stands and the keypad is gone.
        let second = app(["-age-range", "declined", "-uitest-age-service", service])
        second.launch()
        XCTAssertTrue(el(second, "screen-pickCat").waitForExistence(timeout: Live.t(10)), "no pick-a-cat")
        XCTAssertFalse(el(second, "age.confirm").exists, "the keypad came back")
    }

    func testChangeGoesBackToAnEmptyKeypad() {
        let app = app(["-age-range", "declined"])
        app.launch()
        XCTAssertTrue(el(app, "age.confirm").waitForExistence(timeout: Live.t(10)), "no age keypad")
        type(app, "1961")
        el(app, "age.confirm").tap()
        XCTAssertTrue(el(app, "age.change").waitForExistence(timeout: Live.t(5)), "no change button")
        el(app, "age.change").tap()
        XCTAssertTrue(el(app, "age.confirm").waitForExistence(timeout: Live.t(5)), "change didn't go back")
        for i in 0..<4 { XCTAssertEqual(value(el(app, "age.tile.\(i)")) ?? "", "", "tile \(i) kept a digit") }
        XCTAssertFalse(el(app, "screen-pickCat").exists, "a change kept the year")
    }

    /// A mistyped kitten year is put right by Apple's answer, never by retyping (launch review).
    func testAppleCorrectsAMistypedYear() {
        let app = app(["-age-range", "declined", "-age-range-later", "adult"])
        app.launch()
        XCTAssertTrue(el(app, "age.confirm").waitForExistence(timeout: Live.t(10)), "no age keypad")
        type(app, "2019")
        el(app, "age.confirm").tap()
        el(app, "age.yes").tap()
        XCTAssertTrue(el(app, "pickcat.confirm").waitForExistence(timeout: Live.t(10)), "no pick-a-cat")
        el(app, "pickcat.confirm").tap()
        XCTAssertTrue(el(app, "home.settings").waitForExistence(timeout: Live.t(10)), "no Home")
        el(app, "home.settings").tap()
        let check = el(app, "gear.ageCheck")
        XCTAssertTrue(check.waitForExistence(timeout: Live.t(5)), "a kitten has no age check")
        check.tap()
        XCTAssertTrue(until(5) { !self.el(app, "gear.ageCheck").exists }, "Apple's adult answer didn't lift the kitten band")
        XCTAssertFalse(el(app, "kitten.bell").exists, "still a kitten's bell")
    }

    func testADeclineChangesNothing() {
        let app = app(["-age-range", "declined"])
        app.launch()
        XCTAssertTrue(el(app, "age.confirm").waitForExistence(timeout: Live.t(10)), "no age keypad")
        type(app, "2019")
        el(app, "age.confirm").tap()
        el(app, "age.yes").tap()
        XCTAssertTrue(el(app, "pickcat.confirm").waitForExistence(timeout: Live.t(10)), "no pick-a-cat")
        el(app, "pickcat.confirm").tap()
        XCTAssertTrue(el(app, "home.settings").waitForExistence(timeout: Live.t(10)), "no Home")
        el(app, "home.settings").tap()
        XCTAssertTrue(el(app, "gear.ageCheck").waitForExistence(timeout: Live.t(5)), "a kitten has no age check")
        el(app, "gear.ageCheck").tap()
        XCTAssertTrue(el(app, "gear.ageCheck.none").waitForExistence(timeout: Live.t(5)), "no word after a decline")
        XCTAssertTrue(el(app, "kitten.bell").exists, "a decline changed the band")
    }
}
