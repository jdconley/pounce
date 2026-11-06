import XCTest

/// Parent consent (consent design §2; plan decisions 33–39) from the Debug demos: `-demo-kitten
/// <locked|held|pending|on>` is the kitten's own device, `-demo-kittens` with `-stub-accounts
/// signed-in` a parent's. No server needed, except for the notice page, which the app loads from
/// the server. `KITTEN_SHOTS_DIR` in the runner's environment (`TEST_RUNNER_KITTEN_SHOTS_DIR`) also
/// saves each screen as `<name>-<orientation>.png`.
@MainActor
final class KittenTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        // Screenshots in landscape (`TEST_RUNNER_KITTEN_SHOTS_ORIENTATION=landscape`, an iPad).
        let landscape = ProcessInfo.processInfo.environment["KITTEN_SHOTS_ORIENTATION"] == "landscape"
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
    }

    private func launch(_ extra: [String], speed: Double = Live.speed) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = Live.arguments(speed: speed) + ["-uitest-reset", "-seed-people"] + extra
        app.launchEnvironment["POUNCE_API_BASE_URL"] = Live.baseURL
        app.launch()
        return app
    }

    private func kitten(_ scenario: String, _ extra: [String] = []) -> XCUIApplication {
        let app = launch(["-age-band", "kitten", "-demo-kitten", scenario] + extra)
        XCTAssertTrue(el(app, "screen-home").waitForExistence(timeout: Live.t(10)), "no Home")
        return app
    }

    private func openGear(_ app: XCUIApplication) {
        el(app, "home.settings").tap()
        XCTAssertTrue(el(app, "sheet-gear").waitForExistence(timeout: Live.t(5)), "no gear sheet")
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["KITTEN_SHOTS_DIR"], !dir.isEmpty else { return }
        Thread.sleep(forTimeInterval: 1.5)
        let orientation = XCUIDevice.shared.orientation.isLandscape ? "landscape" : "portrait"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name)-\(orientation).png"))
    }

    // MARK: the kitten's bell

    func testLockedBellShowsSixNumerals() {
        let app = kitten("locked")
        openGear(app)
        let bell = el(app, "kitten.bell")
        XCTAssertTrue(bell.waitForExistence(timeout: Live.t(5)), "no kitten bell")
        XCTAssertEqual(value(bell), "locked")
        XCTAssertTrue(el(app, "kitten.code.5").waitForExistence(timeout: Live.t(5)), "no code")
        let digits = (0..<6).map { el(app, "kitten.code.\($0)").label }.joined()
        XCTAssertEqual(digits, "482913")
        XCTAssertFalse(el(app, "gear.kittens").exists, "a kitten has no Kittens panel")
        shot(app, "kitten-bell")
    }

    func testHeldBellShowsNoCode() {
        let app = kitten("locked", ["-kitten-held"])
        openGear(app)
        XCTAssertTrue(until(5) { self.value(self.el(app, "kitten.bell")) == "held" }, "the bell isn't held")
        Thread.sleep(forTimeInterval: Live.pace(1))
        XCTAssertFalse(el(app, "kitten.code").exists, "a held bell shows a code")
    }

    func testLinkedBellSleepsThenRings() {
        let pending = kitten("pending")
        openGear(pending)
        XCTAssertTrue(until(5) { self.value(self.el(pending, "kitten.bell")) == "asleep" }, "pending isn't asleep")
        XCTAssertFalse(el(pending, "kitten.code").exists)
        // One more grown-up: a tap shows a code.
        el(pending, "kitten.bell").tap()
        XCTAssertTrue(el(pending, "kitten.code.0").waitForExistence(timeout: Live.t(5)), "no code for a second parent")
        pending.terminate()
        let on = kitten("on")
        openGear(on)
        XCTAssertTrue(until(5) { self.value(self.el(on, "kitten.bell")) == "on" }, "consent isn't the normal bell")
    }

    func testAnAdultHasNoKittenBellAndNoPanelSignedOut() {
        let app = launch([])
        XCTAssertTrue(el(app, "screen-home").waitForExistence(timeout: Live.t(10)))
        openGear(app)
        Thread.sleep(forTimeInterval: Live.pace(1))
        XCTAssertFalse(el(app, "kitten.bell").exists)
        XCTAssertFalse(el(app, "gear.kittens").exists, "the panel needs a signed-in adult")
    }

    // MARK: the parent's panel

    private func parent(_ extra: [String] = []) -> XCUIApplication {
        let app = launch(["-stub-accounts", "signed-in", "-demo-kittens"] + extra)
        XCTAssertTrue(el(app, "screen-home").waitForExistence(timeout: Live.t(10)), "no Home")
        openGear(app)
        let kittens = el(app, "gear.kittens")
        XCTAssertTrue(kittens.waitForExistence(timeout: Live.t(5)), "no Kittens button for a signed-in adult")
        kittens.tap()
        XCTAssertTrue(el(app, "sheet-kittens").waitForExistence(timeout: Live.t(5)), "no Kittens panel")
        XCTAssertTrue(el(app, "kittens.card.1").waitForExistence(timeout: Live.t(5)), "the kittens didn't load")
        return app
    }

    func testParentPanelTogglesLinksAndRevokes() {
        let app = parent()
        XCTAssertEqual(value(el(app, "kittens.card.0")), "pending")
        // Biscuit's confirmation push reached this parent: the bell with a check.
        XCTAssertEqual(value(el(app, "kittens.card.1")), "confirmed")
        shot(app, "kittens-panel")
        // Kiki is off; a tap turns her on.
        let kiki = el(app, "kittens.person.0.2")
        XCTAssertEqual(value(kiki), "off")
        kiki.tap()
        XCTAssertTrue(until(3) { self.value(kiki) == "on" }, "the toggle didn't turn on")
        // A parent stays on.
        let me = el(app, "kittens.person.0.0")
        me.tap()
        Thread.sleep(forTimeInterval: Live.pace(0.5))
        XCTAssertEqual(value(me), "on")
        // Apple's answers don't change here.
        let leo = el(app, "kittens.person.1.1")
        leo.tap()
        Thread.sleep(forTimeInterval: Live.pace(0.5))
        XCTAssertEqual(value(leo), "off")
        // Revoke Biscuit's.
        el(app, "kittens.revoke.1").tap()
        XCTAssertTrue(until(3) { self.value(self.el(app, "kittens.card.1")) == "pending" }, "revoke didn't take")
        // Link a new kitten by its code: a wrong one shakes and clears.
        el(app, "kittens.add").tap()
        XCTAssertTrue(el(app, "sheet-link").waitForExistence(timeout: Live.t(5)), "no keypad")
        for d in [1, 1, 1, 1, 1, 1] { el(app, "link.key.\(d)").tap() }
        el(app, "link.confirm").tap()
        XCTAssertTrue(until(3) { self.value(self.el(app, "link.tile.0")) == "" }, "a wrong code stayed")
        for d in [4, 8, 2, 9, 1, 3] { el(app, "link.key.\(d)").tap() }
        el(app, "link.confirm").tap()
        XCTAssertTrue(until(5) { !self.el(app, "sheet-link").exists }, "the keypad stayed after a good code")
        XCTAssertTrue(el(app, "kittens.card.2").waitForExistence(timeout: Live.t(5)), "the new kitten isn't listed")
    }

    func testNoticePhoneAndCode() {
        let app = parent()
        el(app, "kittens.phone.0").tap()
        XCTAssertTrue(el(app, "sheet-notice").waitForExistence(timeout: Live.t(5)), "no notice page")
        XCTAssertTrue(el(app, "notice.web").exists)
        let phone = el(app, "notice.phone")
        XCTAssertTrue(phone.exists)
        shot(app, "kitten-notice")
        phone.tap()
        phone.typeText("5551234567")
        // The iPad simulator's hardware keyboard takes the first tap after typing: tap until it goes.
        let code = el(app, "consent.code")
        for _ in 0..<3 where !code.exists {
            el(app, "notice.send").tap()
            _ = code.waitForExistence(timeout: Live.t(2))
        }
        XCTAssertTrue(code.exists, "sending didn't open the code keypad")
        XCTAssertFalse(el(app, "notice.web").exists, "the notice stayed over the code")
        XCTAssertTrue(el(app, "consent.tile.5").exists)
        // A fresh code can't be asked for again for 30 s.
        XCTAssertEqual(value(el(app, "consent.resend")), "waiting")
        shot(app, "consent-code")
        // A wrong code (six numerals checks itself) shakes and clears.
        for d in [1, 1, 1, 1, 1, 1] { el(app, "consent.key.\(d)").tap() }
        XCTAssertTrue(until(3) { self.value(self.el(app, "consent.tile.0")) == "" }, "a wrong code stayed")
        XCTAssertTrue(el(app, "sheet-notice").exists)
        // Another number goes back to the phone field.
        el(app, "consent.number").tap()
        XCTAssertTrue(el(app, "notice.phone").waitForExistence(timeout: Live.t(3)), "no phone field after another number")
        el(app, "notice.close").tap()
        XCTAssertTrue(until(3) { self.value(self.el(app, "kittens.card.0")) == "code" }, "the card isn't waiting for the code")
        // Back in, the sheet opens on the code; the right one turns consent on.
        el(app, "kittens.phone.0").tap()
        XCTAssertTrue(el(app, "consent.code").waitForExistence(timeout: Live.t(5)), "a kitten waiting for a code didn't open on the keypad")
        for d in [1, 3, 5, 7, 9, 0] { el(app, "consent.key.\(d)").tap() }
        allowNotifications()
        XCTAssertTrue(until(8) { !self.el(app, "sheet-notice").exists }, "the sheet stayed after the right code")
        XCTAssertTrue(until(3) { self.value(self.el(app, "kittens.card.0")) == "on" }, "consent isn't on")
        XCTAssertTrue(el(app, "kittens.revoke.0").exists, "no revoke once on")
    }

    /// iOS asks once whether Pounce may send notifications (the confirmation push needs them).
    private func allowNotifications() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: Live.t(3)) { allow.tap() }
    }

    func testConsentNotificationOpensKittensOnThatKitten() {
        let app = launch(["-stub-accounts", "signed-in", "-demo-kittens", "-open-kittens", DemoIDs.biscuit])
        XCTAssertTrue(el(app, "sheet-kittens").waitForExistence(timeout: Live.t(10)), "the notification didn't open Kittens")
        let biscuit = el(app, "kittens.card.1")
        XCTAssertTrue(biscuit.waitForExistence(timeout: Live.t(5)), "the kittens didn't load")
        XCTAssertTrue(biscuit.isSelected, "the panel isn't on the notification's kitten")
        XCTAssertFalse(el(app, "kittens.card.0").isSelected)
        XCTAssertEqual(value(biscuit), "confirmed")
        // The panel scrolled to it: its buttons show.
        let revoke = el(app, "kittens.revoke.1")
        XCTAssertTrue(until(3) { revoke.isHittable }, "the panel didn't scroll to the notification's kitten")
        shot(app, "kittens-confirmed")
        // Its revoke, as the notification's Revoke button does in the background.
        revoke.tap()
        XCTAssertTrue(until(3) { self.value(biscuit) == "pending" }, "revoke didn't take")
    }

    // MARK: the Pounce sheet

    func testUnapprovedPersonIsPadlocked() {
        let app = launch(["-age-band", "kitten", "-demo-kitten", "pending", "-demo-streaks", "-show-us"])
        XCTAssertTrue(el(app, "screen-us").waitForExistence(timeout: Live.t(10)), "no Us screen")
        // The row padlocks Kiki and Nova once the kitten's consent arrives; Mia is approved.
        XCTAssertTrue(until(10) { self.value(self.el(app, "us.pair.1")) == "locked" }, "Kiki isn't padlocked in the row")
        XCTAssertNotEqual(value(el(app, "us.pair.0")), "locked")
        el(app, "us.bell").tap()
        XCTAssertTrue(el(app, "sheet-pounce").waitForExistence(timeout: Live.t(5)))
        XCTAssertFalse(el(app, "pounce.padlock").exists, "Mia is approved")
        XCTAssertEqual(value(el(app, "pounce.send")), "ready")
        el(app, "pounce.close").tap()
        XCTAssertTrue(until(3) { !self.el(app, "sheet-pounce").exists })
        // Kiki isn't.
        // Kiki's pounce waits on the kitten: her card shows once she's the one picked.
        XCTAssertTrue(until(6) {
            if self.el(app, "us.waiting").exists { return true }
            self.el(app, "us.pair.1").tap()
            return self.el(app, "us.waiting").waitForExistence(timeout: Live.t(1))
        }, "Kiki isn't picked")
        el(app, "us.bell").tap()
        XCTAssertTrue(el(app, "pounce.padlock").waitForExistence(timeout: Live.t(5)), "Kiki isn't padlocked")
        XCTAssertEqual(value(el(app, "pounce.send")), "locked")
        shot(app, "pounce-padlock")
        el(app, "pounce.send").tap()
        Thread.sleep(forTimeInterval: Live.pace(1))
        XCTAssertTrue(el(app, "sheet-pounce").exists, "a padlocked pounce went out")
    }
}

/// The demo kittens' ids (`DemoKittenService`), which the UI test target can't import.
private enum DemoIDs {
    static let biscuit = "k_demoBiscuitAAAAAAAAAAAA"
}
