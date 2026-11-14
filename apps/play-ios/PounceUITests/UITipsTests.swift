import XCTest

/// UI tips (`Pounce/Shell/Tips.swift`): one bubble at a time pointing at a control, gone once the
/// control is used. No server needed. Tips are off under `-uitest-reset` and the demos, so these
/// launch with `-ui-tips`.
///
/// `UITIPS_SHOTS_DIR` in the runner's environment (`TEST_RUNNER_UITIPS_SHOTS_DIR`) makes
/// `testShots` save one screenshot per tip as `<name>-<orientation>.png`; `UITIPS_ONLY` (names,
/// comma separated) narrows it, and `UITIPS_ORIENTATION=landscape` turns an iPad.
@MainActor
final class UITipsTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        let landscape = ProcessInfo.processInfo.environment["UITIPS_ORIENTATION"] == "landscape"
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
    }

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = Live.arguments() + ["-uitest-reset"] + extra
        app.launchEnvironment["POUNCE_API_BASE_URL"] = Live.baseURL
        app.launch()
        return app
    }

    /// The tip showing now, by name (nil: none).
    private func tip(_ app: XCUIApplication) -> String? {
        value(el(app, "tip"))
    }

    /// A brand-new player picks a cat and lands on Home: the first tip is Cat Tower's Play, and
    /// starting a game (using the control) puts it away. The next tips come one at a time.
    func testFirstHomeVisitShowsThePlayTipAndPlayingPutsItAway() {
        let app = launch(["-age-band", "adult", "-ui-tips"])
        onboard(app)
        XCTAssertTrue(until(10) { self.tip(app) == "ui.home.shelf" }, "no Play tip on a first Home visit: \(String(describing: tip(app)))")
        let bubble = el(app, "tip")
        XCTAssertEqual(label(bubble), "Tap Play to start a game.")
        // It never covers the card it points at, and stays on screen.
        let card = el(app, "home.newGame").frame
        XCTAssertTrue(app.frame.contains(bubble.frame), "the bubble runs off screen: \(bubble.frame)")
        XCTAssertFalse(bubble.frame.intersects(card.insetBy(dx: 0, dy: 2)) && card.height < 200,
                       "the bubble covers the card: \(bubble.frame) over \(card)")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "tip").count, 1, "more than one tip")
        el(app, "home.newGame").tap()
        XCTAssertTrue(until(5) { self.tip(app) != "ui.home.shelf" }, "the Play tip stayed after Play")
    }

    /// A tap on the bubble puts it away; the next one waits a moment, then it's Practice, then
    /// Join, and using Join (shown or not) means it never shows. Three at most on this visit.
    func testTipsComeOneAtATimeAndUsingAControlTeachesIt() {
        let app = launch(["-age-band", "adult", "-ui-tips"])
        onboard(app)
        XCTAssertTrue(until(10) { self.tip(app) == "ui.home.shelf" })
        el(app, "tip").tap()
        XCTAssertTrue(until(2) { self.tip(app) != "ui.home.shelf" }, "the bubble stayed after a tap")
        // One tip a visit to Home (first-run funnel): nothing follows it.
        Thread.sleep(forTimeInterval: Live.pace(3, floor: 0.6))
        XCTAssertNil(tip(app), "a second tip on the same visit")
        // Join used before its tip ever showed: learned, so it never comes.
        el(app, "home.join").tap()
        XCTAssertTrue(el(app, "screen-join").waitForExistence(timeout: Live.t(5)), "no Join screen")
        XCTAssertNil(tip(app), "a Home tip over Join")
        el(app, "join.back").tap()
        XCTAssertTrue(el(app, "screen-home").waitForExistence(timeout: Live.t(5)))
        // The next visit gets the next tip, never Join's.
        XCTAssertTrue(until(10) { self.tip(app) == "ui.home.practice" }, "no Practice tip next visit: \(String(describing: tip(app)))")
    }

    /// Off unless asked: a UI test run (and every demo) shows no tips.
    func testTipsStayOffInTestRunsAndDemos() {
        for extra in [["-seed-people"], ["-seed-people", "-demo-home"], ["-demo", "lobbyReady"]] {
            let app = launch(extra)
            Thread.sleep(forTimeInterval: Live.pace(4, floor: 1.5))
            XCTAssertFalse(el(app, "tip").exists, "a tip showed under \(extra)")
            app.terminate()
        }
    }

    // MARK: screenshots

    private struct Shot {
        let name: String
        let args: [String]
        let tip: String
        var before: (XCUIApplication) -> Void = { _ in }
    }

    private static let shots: [Shot] = [
        Shot(name: "home-play", args: ["-seed-people"], tip: "ui.home.shelf"),
        Shot(name: "home-practice", args: ["-seed-people", "-tips-seen", "ui.home.shelf"], tip: "ui.home.practice"),
        Shot(name: "home-join", args: ["-seed-people", "-tips-seen", "ui.home.shelf,ui.home.practice"], tip: "ui.home.join"),
        Shot(name: "home-tables", args: ["-seed-people", "-demo-home", "-tips-seen", "ui.home.shelf"], tip: "ui.home.tables"),
        Shot(name: "home-archive", args: ["-seed-people", "-demo-home", "-tips-seen", "ui.home.shelf,ui.home.tables,ui.home.join"], tip: "ui.home.archive"),
        Shot(name: "home-gift", args: ["-seed-people", "-demo-streaks", "-tips-seen", "ui.home.shelf"], tip: "ui.home.gift"),
        Shot(name: "home-streak", args: ["-seed-people", "-demo-streaks", "-tips-seen", "ui.home.shelf,ui.home.gift,ui.home.tables,ui.home.practice,ui.home.join"],
             tip: "ui.home.streak"),
        Shot(name: "home-update", args: ["-seed-people", "-age-band", "adult", "-demo-update", "soft", "-tips-seen", "ui.home.shelf"],
             tip: "ui.home.update"),
        Shot(name: "lobby-start", args: ["-seed-people", "-demo", "lobbyReady"], tip: "ui.lobby.start"),
        Shot(name: "gear-alerts", args: ["-seed-people", "-age-band", "adult", "-show-gear"], tip: "ui.gear.alerts"),
        Shot(name: "us-bell", args: ["-seed-people", "-demo-streaks", "-show-us"], tip: "ui.us.bell"),
        Shot(name: "tiles", args: ["-seed-people", "-demo", "tiles"], tip: "ui.tiles."),
    ]

    func testShots() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["UITIPS_SHOTS_DIR"], !dir.isEmpty else { throw XCTSkip("UITIPS_SHOTS_DIR not set") }
        let only = env["UITIPS_ONLY"].flatMap { $0.isEmpty ? nil : Set($0.split(separator: ",").map(String.init)) }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let orientation = XCUIDevice.shared.orientation.isLandscape ? "landscape" : "portrait"
        var missed: [String] = []
        for shot in Self.shots where only?.contains(shot.name) ?? true {
            let app = launch(shot.args + ["-ui-tips"])
            shot.before(app)
            if until(12, { self.tip(app)?.hasPrefix(shot.tip) == true }) {
                Thread.sleep(forTimeInterval: 1.2)  // the spring settles
                try XCUIScreen.main.screenshot().pngRepresentation
                    .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(shot.name)-\(orientation).png"))
            } else {
                missed.append("\(shot.name) (\(tip(app) ?? "no tip"))")
            }
            app.terminate()
        }
        XCTAssertTrue(missed.isEmpty, "no tip for \(missed)")
    }
}
