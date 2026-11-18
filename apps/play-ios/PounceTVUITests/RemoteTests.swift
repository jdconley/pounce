import XCTest

/// The TV driven by the Siri Remote alone: real `XCUIRemote` presses, no DEBUG shortcuts, on the
/// shell's demo (`-demo tv-shell`: a poster makes a table whose lobby fills and starts when the
/// test says). After every press something has the focus (`press`), so Select and Menu always
/// have somewhere to go.
@MainActor
final class RemoteTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Home: Cat Tower has the focus and Down/Up move between the posters. Select on a poster
    /// makes a table and shows its lobby, where Change game has the focus while nobody sits and
    /// swaps the game. The paw is reachable from there, and Select on it opens the menu.
    func testAPosterMakesATableAndChangeGameSwapsIt() {
        let app = launchHome()
        press(app, .down, to: "tv.poster.tiles")
        press(app, .up, to: "tv.poster.cat-tower")

        press(app, .select)
        XCTAssertTrue(until(10) { self.label(self.el(app, "tv.lobby.game")) == "Cat Tower" }, "Select on Cat Tower didn't show its lobby")
        XCTAssertTrue(waitForFocus(app, "tv.lobby.changeGame"), "Change game doesn't have the focus while nobody sits: \(focusedID(app) ?? "nothing")")

        press(app, .select)
        XCTAssertTrue(until(10) { self.label(self.el(app, "tv.lobby.game")) == "Tuna Tiles" }, "Change game didn't swap the game")
        XCTAssertTrue(waitForFocus(app, "tv.lobby.changeGame"), "Change game lost the focus in the new lobby: \(focusedID(app) ?? "nothing")")

        // The paw, in the corner: from Change game, Down or Right reaches it.
        press(app, .down)
        if !waitForFocus(app, "tv.paw", timeout: 2) { press(app, .right) }
        XCTAssertTrue(waitForFocus(app, "tv.paw"), "the paw can't be reached from Change game: \(focusedID(app) ?? "nothing")")
        press(app, .select)
        XCTAssertTrue(waitForFocus(app, "tv.menu.link"), "Select on the paw didn't open the menu: \(focusedID(app) ?? "nothing")")
        press(app, .menu)
        XCTAssertTrue(until(5) { !self.el(app, "tv.menu.link").exists }, "Menu didn't shut the menu: \(focusedID(app) ?? "nothing")")
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// The menu at the lobby and at the table: Down and Up move through Link another table, Sound
    /// and Leave table; Sound says what it is now; Link another table shows the link with Back
    /// focused; each Menu press goes back one level. At the table Menu opens the menu rather than
    /// leaving the app, and a long Select or Play/Pause does nothing harmful.
    func testTheMenuAtTheLobbyAndTheTable() {
        let app = launchHome()
        press(app, .select)
        XCTAssertTrue(el(app, "tv.lobby.game").waitForExistence(timeout: Live.t(10)), "no lobby")
        // The lobby is live (its room came over the socket) before the first go-ahead.
        XCTAssertTrue(waitForFocus(app, "tv.lobby.changeGame"), "the empty lobby has no Change game focused")
        Live.releaseDemo()
        XCTAssertTrue(until(10) { !self.el(app, "tv.lobby.changeGame").exists }, "nobody sat down")
        XCTAssertTrue(waitForFocus(app, "tv.paw"), "the paw doesn't have the focus once Change game is gone: \(focusedID(app) ?? "nothing")")

        // Lobby: through the menu and back.
        press(app, .select)
        XCTAssertTrue(waitForFocus(app, "tv.menu.link"), "Select on the paw didn't open the menu")
        press(app, .down, to: "tv.menu.sound")
        press(app, .down, to: "tv.menu.leave")
        Thread.sleep(forTimeInterval: 0.5)
        press(app, .down, to: "tv.menu.leave", "Down past the last choice moved the focus off the menu")
        press(app, .up, to: "tv.menu.sound")
        XCTAssertEqual(label(el(app, "tv.menu.sound")), "Sound on")
        press(app, .select)
        XCTAssertTrue(until(3) { self.label(self.el(app, "tv.menu.sound")) == "Sound off" }, "Sound didn't turn off")
        press(app, .select)
        XCTAssertTrue(until(3) { self.label(self.el(app, "tv.menu.sound")) == "Sound on" }, "Sound didn't turn on again")
        press(app, .up, to: "tv.menu.link")
        press(app, .select)
        XCTAssertTrue(waitForFocus(app, "tv.menu.back"), "the link opened without Back focused: \(focusedID(app) ?? "nothing")")
        XCTAssertTrue(until(5) { (self.label(self.el(app, "tv.menu.code")) ?? "").contains("K T N P W S") }, "the link's code isn't shown")
        press(app, .menu)
        XCTAssertTrue(waitForFocus(app, "tv.menu.link"), "Menu from the link didn't go back to the choices: \(focusedID(app) ?? "nothing")")
        press(app, .menu)
        XCTAssertTrue(waitForFocus(app, "tv.paw"), "Menu from the choices didn't shut the menu: \(focusedID(app) ?? "nothing")")

        // The game starts: the paw keeps the focus over the table.
        Live.releaseDemo()
        XCTAssertTrue(el(app, "table.deck").waitForExistence(timeout: Live.t(20)), "the game never started")
        XCTAssertTrue(waitForFocus(app, "tv.paw"), "the paw lost the focus as the table came up: \(focusedID(app) ?? "nothing")")

        // Menu at the table opens the menu; it never leaves the app mid-game.
        press(app, .menu)
        XCTAssertTrue(waitForFocus(app, "tv.menu.link"), "Menu at the table didn't open the menu")
        XCTAssertEqual(app.state, .runningForeground, "Menu at the table left the app")
        press(app, .down, to: "tv.menu.sound")
        press(app, .menu)
        XCTAssertTrue(waitForFocus(app, "tv.paw"), "Menu didn't shut the menu at the table")
        // Select on the paw opens it too.
        press(app, .select)
        XCTAssertTrue(waitForFocus(app, "tv.menu.link"), "Select on the paw didn't open the menu at the table")
        press(app, .menu)
        XCTAssertTrue(waitForFocus(app, "tv.paw"))

        // A long Select on the paw acts as a Select: the menu opens over the table, and nothing
        // else happens. Then Play/Pause: the table stays, and so does the focus.
        press(app, .select, forDuration: 1.5, to: "tv.menu.link", "a long Select didn't open the menu as a Select does")
        XCTAssertTrue(el(app, "table.deck").exists, "a long Select left the table")
        press(app, .menu, to: "tv.paw")
        press(app, .playPause)
        XCTAssertTrue(el(app, "table.deck").exists, "Play/Pause left the table")
        XCTAssertFalse(el(app, "tv.menu.link").exists, "Play/Pause opened the menu")
        XCTAssertTrue(waitForFocus(app, "tv.paw"), "Play/Pause moved the focus: \(focusedID(app) ?? "nothing")")
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// Game over keeps the paw focused; Leave table goes home with Cat Tower focused; Menu at
    /// home leaves the app, as tvOS users expect.
    func testLeaveTableGoesHomeAndMenuAtHomeLeavesTheApp() {
        let app = launchHome()
        press(app, .select)
        XCTAssertTrue(el(app, "tv.lobby.game").waitForExistence(timeout: Live.t(10)), "no lobby")
        // The lobby is live (its room came over the socket) before the first go-ahead.
        XCTAssertTrue(waitForFocus(app, "tv.lobby.changeGame"), "the empty lobby has no Change game focused")
        Live.releaseDemo()
        XCTAssertTrue(until(10) { !self.el(app, "tv.lobby.changeGame").exists }, "nobody sat down")
        Live.releaseDemo()
        XCTAssertTrue(el(app, "table.deck").waitForExistence(timeout: Live.t(20)), "the game never started")
        Live.endDemo()
        XCTAssertTrue(el(app, "tv.over.title").waitForExistence(timeout: Live.t(30)), "game over never showed")
        XCTAssertTrue(waitForFocus(app, "tv.paw"), "the paw doesn't have the focus at game over: \(focusedID(app) ?? "nothing")")

        press(app, .select)
        XCTAssertTrue(waitForFocus(app, "tv.menu.link"), "Select on the paw didn't open the menu at game over")
        press(app, .down, to: "tv.menu.sound")
        press(app, .down, to: "tv.menu.leave")
        press(app, .select)
        XCTAssertTrue(waitForFocus(app, "tv.poster.cat-tower", timeout: 10), "Leave table didn't go home with Cat Tower focused: \(focusedID(app) ?? "nothing")")
        XCTAssertFalse(el(app, "tv.paw").exists, "the paw stayed after leaving the table")

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: Live.t(10)), "Menu at home didn't leave the app: \(app.state.rawValue)")
    }

    // MARK: helpers

    /// The shell's demo at home, its link shown and Cat Tower focused.
    private func launchHome() -> XCUIApplication {
        let app = Live.demo("tv-shell", speed: 4)
        app.launch()
        XCTAssertTrue(waitForFocus(app, "tv.poster.cat-tower", timeout: 20), "home didn't open with Cat Tower focused: \(focusedID(app) ?? "nothing")")
        XCTAssertTrue(until(5) { (self.label(self.el(app, "tv.home.code")) ?? "").contains("K T N P W S") }, "home's link isn't shown")
        return app
    }
}
