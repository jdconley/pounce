import XCTest

/// Streaks on Home, the trophy room and adding people (trophy room design §1, §3, §4), drawn from
/// `DemoFixtures.streaks()` under `-demo-streaks` (own streak 12 with a nap yesterday; Mia 128,
/// Kiki 9, Nova 41), `-demo-streaks empty` (nobody connected yet): no server needed.
/// `TROPHY_SHOTS_DIR` in the runner's environment (`TEST_RUNNER_TROPHY_SHOTS_DIR`) also saves each
/// screen as `<name>-<orientation>.png`; `TROPHY_SHOTS_ORIENTATION=landscape` turns an iPad.
@MainActor
final class TrophyTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        let landscape = ProcessInfo.processInfo.environment["TROPHY_SHOTS_ORIENTATION"] == "landscape"
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
    }

    private func launch(_ extra: [String] = [], streaks: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = Live.arguments() + ["-uitest-reset", "-seed-people", "-demo-streaks"] + (streaks.map { [$0] } ?? []) + extra
        app.launchEnvironment["POUNCE_API_BASE_URL"] = Live.baseURL
        app.launch()
        return app
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["TROPHY_SHOTS_DIR"], !dir.isEmpty else { return }
        Thread.sleep(forTimeInterval: 1.5)
        let orientation = XCUIDevice.shared.orientation.isLandscape ? "landscape" : "portrait"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name)-\(orientation).png"))
    }

    private func trophies(_ app: XCUIApplication) {
        XCTAssertTrue(el(app, "screen-trophies").waitForExistence(timeout: Live.t(10)), "no trophy room")
    }

    // MARK: Home's strip (§1)

    func testStripOrder() {
        let app = launch()
        let own = el(app, "home.own")
        XCTAssertTrue(own.waitForExistence(timeout: Live.t(10)), "no own streak on Home")
        XCTAssertEqual(value(own), "12|0|napped")
        let top = el(app, "home.streak")
        XCTAssertEqual(value(top), "128|1|0|normal", "the top pair keeps its badge")
        let add = el(app, "home.add")
        XCTAssertTrue(add.exists)
        XCTAssertEqual(value(add), "small")
        let xs = ["home.own", "home.streak", "home.pair.1", "home.pair.2"].map { el(app, $0).frame.minX }
        XCTAssertEqual(xs, xs.sorted(), "own, then the pairs in order: \(xs)")
        // Invite is in the dock, beside Join, not in the strip.
        XCTAssertTrue(el(app, "home.dock").frame.contains(add.frame), "Invite isn't in the dock")
        XCTAssertFalse(el(app, "home.strip").frame.contains(add.frame), "Invite is still in the strip")
        XCTAssertTrue(el(app, "home.gift").exists, "the gift still waits on Home")
        XCTAssertTrue(el(app, "home.pounce").exists, "Kiki's pounce still rings on Home")
        shot(app, "strip")
    }

    func testWithNobodyConnectedInviteSitsBesideJoin() {
        let app = launch(streaks: "empty")
        let add = el(app, "home.add")
        XCTAssertTrue(add.waitForExistence(timeout: Live.t(10)), "no Invite on Home")
        XCTAssertEqual(value(add), "big", "Invite doesn't call out while nobody is connected")
        XCTAssertEqual(add.label, "Invite someone", "Invite says what it does")
        XCTAssertTrue(el(app, "home.own").exists)
        XCTAssertFalse(el(app, "home.streak").exists)
        let join = el(app, "home.join")
        // It bounces while nobody is connected, so: inside the dock, beside Join.
        let dock = el(app, "home.dock").frame
        XCTAssertTrue(dock.contains(CGPoint(x: add.frame.midX, y: add.frame.midY)), "Invite isn't in the dock")
        XCTAssertTrue(dock.contains(CGPoint(x: join.frame.midX, y: join.frame.midY)), "Join isn't in the dock")
        XCTAssertLessThan(add.frame.maxX, join.frame.minX, "Invite comes before Join")
        shot(app, "strip-empty")
    }

    func testPairChipOpensUsOnThatPair() {
        let app = launch()
        let kiki = el(app, "home.pair.1")
        XCTAssertTrue(kiki.waitForExistence(timeout: Live.t(10)))
        kiki.tap()
        XCTAssertTrue(el(app, "screen-us").waitForExistence(timeout: Live.t(10)), "no Us screen")
        XCTAssertTrue(until(5) { self.label(self.el(app, "us.count")) == "9" }, "Us didn't open on Kiki")
    }

    // MARK: the trophy room (§3)

    func testOwnOpensTheTrophyRoom() {
        let app = launch()
        let own = el(app, "home.own")
        XCTAssertTrue(own.waitForExistence(timeout: Live.t(10)))
        own.tap()
        trophies(app)
        XCTAssertTrue(el(app, "trophies.record.current").waitForExistence(timeout: Live.t(5)))
        XCTAssertEqual(value(el(app, "trophies.record.current")), "12")
        XCTAssertEqual(value(el(app, "trophies.record.best")), "30")
        XCTAssertEqual(value(el(app, "trophies.record.longestPair")), "128")
        XCTAssertEqual(value(el(app, "trophies.record.totalDays")), "96")
        XCTAssertEqual(value(el(app, "trophies.record.perfectWeeks")), "6")
        XCTAssertEqual(label(el(app, "trophies.count")), "12")
        el(app, "trophies.back").tap()
        XCTAssertTrue(el(app, "home.own").waitForExistence(timeout: Live.t(10)))
    }

    func testTrophyRoomShowsTheShelfAndWhatsStillToEarn() {
        let app = launch(["-show-trophies"])
        trophies(app)
        XCTAssertTrue(el(app, "trophies.shelf.condo-7").waitForExistence(timeout: Live.t(5)), "the condo isn't on the shelf")
        XCTAssertTrue(el(app, "trophies.shelf.rug-night-sky").exists)
        XCTAssertTrue(el(app, "trophies.shelf.toy-golden-fish").exists)
        shot(app, "trophies")
        // Locked silhouettes with rings: the next condo stage first (141 of 150 days together).
        let next = el(app, "trophies.locked.condo-8")
        for _ in 0..<6 where !next.exists || !next.isHittable { app.swipeUp() }
        XCTAssertTrue(next.exists, "no silhouette for the next condo stage")
        XCTAssertEqual(value(next), "150|94")
        XCTAssertFalse(el(app, "trophies.locked.condo-7").exists, "an earned stage is locked")
        shot(app, "trophies-locked")
    }

    func testTrophyRoomConnectionsOpenUs() {
        let app = launch(["-show-trophies"])
        trophies(app)
        let kiki = el(app, "trophies.pair.1")
        XCTAssertTrue(kiki.waitForExistence(timeout: Live.t(5)))
        kiki.tap()
        XCTAssertTrue(el(app, "screen-us").waitForExistence(timeout: Live.t(10)))
        XCTAssertTrue(until(5) { self.label(self.el(app, "us.count")) == "9" })
        // And back from the Us screen's trophy.
        el(app, "us.trophies").tap()
        trophies(app)
    }

    // MARK: adding someone (§4)

    func testInviteOpensTheInviteWithItsQR() {
        let app = launch()
        let add = el(app, "home.add")
        XCTAssertTrue(add.waitForExistence(timeout: Live.t(10)))
        add.tap()
        XCTAssertTrue(el(app, "sheet-invite").waitForExistence(timeout: Live.t(5)), "no invite sheet")
        let qr = el(app, "invite.qr")
        XCTAssertTrue(qr.waitForExistence(timeout: Live.t(5)), "no QR")
        XCTAssertTrue(value(qr)?.hasPrefix("https://play.conleychaos.com/p/DemoLink") == true, "the QR is the link: \(value(qr) ?? "")")
        XCTAssertTrue(el(app, "invite.share").exists, "an adult can send the link")
        XCTAssertFalse(el(app, "invite.code").exists)
        shot(app, "invite")
        el(app, "invite.close").tap()
        XCTAssertTrue(until(3) { !self.el(app, "sheet-invite").exists })
    }

    func testTrophyRoomPlusOpensTheInvite() {
        let app = launch(["-show-trophies"])
        trophies(app)
        el(app, "trophies.add").tap()
        XCTAssertTrue(el(app, "invite.qr").waitForExistence(timeout: Live.t(5)))
    }

    func testKittenInviteShowsARoomCodeAndNoLink() {
        let app = launch(["-age-band", "kitten", "-show-invite"])
        XCTAssertTrue(el(app, "sheet-invite").waitForExistence(timeout: Live.t(10)), "no invite sheet")
        let code = el(app, "invite.code")
        XCTAssertTrue(code.waitForExistence(timeout: Live.t(5)), "no room code")
        XCTAssertEqual(value(code), "TB4XN")
        XCTAssertEqual(value(el(app, "invite.qr")), "https://play.conleychaos.com/j/TB4XN")
        XCTAssertFalse(el(app, "invite.share").exists, "a kitten's device sends no link")
        XCTAssertTrue(el(app, "invite.play").exists)
        shot(app, "invite-kitten")
    }
}
