import XCTest

/// Home's game shelf (game picker): one card per `GameCatalog` game. Cat Tower can be started
/// (its card keeps Create's id, `home.newGame`); the tile game is on the shelf as "Coming soon"
/// and answers a tap with a note, never a table. No server needed: `-demo-home` puts sample
/// tables on Home and `-demo-streaks` the strip.
/// `SHELF_SHOTS_DIR` in the runner's environment (`TEST_RUNNER_SHELF_SHOTS_DIR`) also saves each
/// screen as `<name>-<orientation>.png`; `SHELF_SHOTS_ORIENTATION=landscape` turns an iPad.
@MainActor
final class GameShelfTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        let landscape = ProcessInfo.processInfo.environment["SHELF_SHOTS_ORIENTATION"] == "landscape"
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = Live.arguments() + ["-uitest-reset", "-seed-people"] + extra
        app.launchEnvironment["POUNCE_API_BASE_URL"] = Live.baseURL
        app.launch()
        XCTAssertTrue(el(app, "screen-home").waitForExistence(timeout: Live.t(10)), "no Home")
        return app
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SHELF_SHOTS_DIR"], !dir.isEmpty else { return }
        Thread.sleep(forTimeInterval: 1.5)
        let orientation = XCUIDevice.shared.orientation.isLandscape ? "landscape" : "portrait"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name)-\(orientation).png"))
    }

    func testTheShelfListsEveryGameAndLeadsWithNoTables() {
        let app = launch(["-demo-streaks", "empty"])
        let catTower = el(app, "home.newGame")
        XCTAssertTrue(catTower.waitForExistence(timeout: Live.t(10)), "no Cat Tower card")
        XCTAssertEqual(label(catTower), "Cat Tower. Rummy up a ten-shelf tower. 2 to 6 players.")
        let tiles = el(app, "home.game.tiles")
        XCTAssertTrue(tiles.exists, "no card for the game on the way")
        XCTAssertEqual(label(tiles), "Tuna Tiles, coming soon. Tile rummy. Yarn is wild. 2 to 4 players.")
        XCTAssertFalse(el(app, "home.tables").exists, "tables with no table")
        // Everything Home did before is still here.
        for id in ["home.join", "home.practice", "home.people", "home.settings", "home.hero", "home.own", "home.add"] {
            XCTAssertTrue(el(app, id).exists, "\(id) is gone")
        }
        XCTAssertTrue(catTower.isHittable, "Cat Tower's card can't be tapped as Home opens")
        shot(app, "empty")
    }

    func testAGameOnTheWayAnswersATapAndStartsNothing() {
        let app = launch()
        let tiles = el(app, "home.game.tiles")
        XCTAssertTrue(tiles.waitForExistence(timeout: Live.t(10)), "no card for the game on the way")
        XCTAssertEqual(value(tiles) ?? "", "", "the note before any tap")
        tiles.tap()
        XCTAssertTrue(until(3) { self.value(tiles) == "Not ready yet." }, "no note after the tap")
        shot(app, "coming-soon-tap")
        XCTAssertTrue(el(app, "screen-home").exists, "the tap left Home")
        XCTAssertFalse(el(app, "home.createError").exists, "the tap tried to start a table")
        XCTAssertTrue(until(8) { (self.value(tiles) ?? "") == "" }, "the note never went away")
        XCTAssertTrue(el(app, "screen-home").exists, "left Home after the note")
    }

    func testTablesLeadWhileAGameIsGoing() {
        let app = launch(["-demo-streaks", "-demo-home"])
        let tables = el(app, "home.tables")
        XCTAssertTrue(tables.waitForExistence(timeout: Live.t(10)), "no tables")
        XCTAssertEqual(label(el(app, "home.yourTurn")), "2 turns")
        XCTAssertFalse(el(app, "home.practice").exists, "practice with tables in progress")
        XCTAssertTrue(el(app, "home.join").isHittable, "Join can't be reached with tables on Home")
        let catTower = el(app, "home.newGame")
        XCTAssertTrue(catTower.exists, "no Cat Tower card under the tables")
        if app.windows.firstMatch.frame.width < 700 || !XCUIDevice.shared.orientation.isLandscape {
            XCTAssertLessThan(tables.frame.minY, catTower.frame.minY, "the shelf is above tables in progress")
        } else {
            XCTAssertLessThan(tables.frame.minX, catTower.frame.minX, "the shelf comes before tables in progress")
        }
        shot(app, "tables")
    }

    /// VoiceOver's order is the accessibility tree's: the player bar (the owner's cat, the strip,
    /// the gear), the column from the top (tables, shelf), then the dock.
    func testVoiceOverReadsHomeTopToBottom() throws {
        let app = launch(["-demo-streaks", "-demo-home"])
        XCTAssertTrue(el(app, "home.newGame").waitForExistence(timeout: Live.t(10)), "no Cat Tower card")
        let wanted = ["home.people", "home.own", "home.settings", "home.table.M3W7Z", "home.newGame", "home.game.tiles", "home.join"]
        var seen: [String] = []
        func walk(_ node: XCUIElementSnapshot) {
            if wanted.contains(node.identifier), !seen.contains(node.identifier) { seen.append(node.identifier) }
            node.children.forEach(walk)
        }
        walk(try el(app, "screen-home").snapshot())
        XCTAssertEqual(seen, wanted)
    }

    /// The player bar, the column and the dock never overlap: the owner's cat sits in the player
    /// bar, clear of the tables and the shelf, and the column ends where the dock begins.
    func testNothingOverlapsTheBars() {
        for extra in [["-demo-streaks", "empty"], ["-demo-streaks", "-demo-home"]] {
            let app = launch(extra)
            XCTAssertTrue(el(app, "home.newGame").waitForExistence(timeout: Live.t(10)), "no Cat Tower card")
            let cat = el(app, "home.people").frame
            let gear = el(app, "home.settings").frame
            let dock = el(app, "home.dock").frame
            let shelf = el(app, "home.shelf").frame
            XCTAssertLessThanOrEqual(cat.maxY, shelf.minY, "the cat reaches into the shelf")
            XCTAssertFalse(cat.intersects(el(app, "home.strip").frame), "the cat covers the strip")
            XCTAssertFalse(gear.intersects(el(app, "home.strip").frame), "the gear covers the strip")
            if el(app, "home.tables").exists {
                XCTAssertLessThanOrEqual(cat.maxY, el(app, "home.tables").frame.minY + 20, "the cat reaches into the tables")
            }
            XCTAssertLessThan(cat.minY, dock.minY - 200, "the cat isn't up top")
            // Everything the column shows ends at the dock's edge.
            let catTower = el(app, "home.newGame")
            if catTower.isHittable { XCTAssertLessThanOrEqual(catTower.frame.minY, dock.minY) }
            XCTAssertTrue(el(app, "home.join").isHittable, "Join can't be reached")
            app.terminate()
        }
    }

    func testTheRulesChipOpensHowToPlay() {
        let app = launch()
        let chip = el(app, "home.hero")
        XCTAssertTrue(chip.waitForExistence(timeout: Live.t(10)), "no How to play on Cat Tower's card")
        chip.tap()
        XCTAssertTrue(el(app, "sheet-rules").waitForExistence(timeout: Live.t(5)), "no rules")
    }

    /// At an accessibility text size the cards grow, the column scrolls, and every game and
    /// Join can still be reached.
    func testBigTextKeepsEveryGameInReach() {
        let app = launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL", "-demo-streaks", "empty"])
        let catTower = el(app, "home.newGame")
        XCTAssertTrue(catTower.waitForExistence(timeout: Live.t(10)), "no Cat Tower card")
        XCTAssertTrue(el(app, "home.join").isHittable, "Join can't be reached at a big text size")
        shot(app, "big-text")
        let tiles = el(app, "home.game.tiles")
        XCTAssertTrue(tiles.exists, "no card for the game on the way")
        // Clear of the bottom bar, not just somewhere under it.
        let join = el(app, "home.join")
        for _ in 0..<6 where tiles.frame.maxY > join.frame.minY - 40 { app.swipeUp() }
        XCTAssertLessThan(tiles.frame.maxY, join.frame.minY, "the second game can't be scrolled clear of the bottom bar")
        shot(app, "big-text-scrolled")
    }

    /// The other screenshots for `Art/screenshots/game-picker/` (skipped without a folder).
    func testShots() throws {
        guard ProcessInfo.processInfo.environment["SHELF_SHOTS_DIR"]?.isEmpty == false else { throw XCTSkip("no SHELF_SHOTS_DIR") }
        shot(launch(["-demo-streaks", "empty", "-age-band", "kitten"]), "under-13")
        shot(launch(["-demo-streaks", "-shelf", "six"]), "six-games")
        shot(launch(["-demo-streaks", "-shelf", "all"]), "both-available")
    }
}
