import XCTest

/// Tonight's board at 1080p for review (DEBUG `-demo tv-board`, no server): the board on a busy
/// evening, the watch card, a watched run, the board's menu, home with its three posters, and the
/// board's link panel. Each shot is attached to the result, and written to `TV_SHOTS_DIR`
/// (`TEST_RUNNER_TV_SHOTS_DIR` for xcodebuild) as `appletv-<name>.png` when it's set.
@MainActor
final class BoardShotTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func shot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let note = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        note.name = "appletv-\(name)"
        note.lifetime = .keepAlways
        add(note)
        if let dir = ProcessInfo.processInfo.environment["TV_SHOTS_DIR"] {
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("appletv-\(name).png"))
        }
    }

    func testTheBoardItsCardAndWatchingAndHome() {
        let app = Live.demo("tv-board", speed: 1)
        // Silent on a Mac: speed 1 plays real sound.
        app.launchArguments += ["-settings.soundOn", "<false/>", "-tv.soundOn", "<false/>"]
        // The App Store's people (`AppStore/README.md`): `TEST_RUNNER_POUNCE_DEMO_CAST` for xcodebuild.
        if let cast = ProcessInfo.processInfo.environment["POUNCE_DEMO_CAST"] { app.launchEnvironment["POUNCE_DEMO_CAST"] = cast }
        app.launch()
        XCTAssertTrue(el(app, "tv.board.game.box-fort").waitForExistence(timeout: Live.t(20)), "no board")
        // A few beats in, so every card has rows and someone is playing.
        Thread.sleep(forTimeInterval: 7)
        shot("board")

        Live.releaseDemo()
        XCTAssertTrue(el(app, "tv.watch.card").waitForExistence(timeout: Live.t(10)), "no watch card")
        XCTAssertTrue(waitForFocus(app, "tv.watch.notNow"), "Not now isn't focused")
        Thread.sleep(forTimeInterval: 0.8)
        shot("card")
        press(app, .left, to: "tv.watch.watch")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(el(app, "tv.watch.view.sniff").waitForExistence(timeout: Live.t(5)), "no watch view")
        // Sniff's own view, three guesses in (the demo guesses 10 s after the offer, then every 1.5 s).
        Thread.sleep(forTimeInterval: 10.5)
        shot("watch")
        XCTAssertTrue(el(app, "tv.watch.ended").waitForExistence(timeout: Live.t(25)), "the watched run never ended")
        Thread.sleep(forTimeInterval: 0.8)
        shot("watch-ended")
        XCTAssertTrue(until(12) { !self.el(app, "tv.watch.ended").exists }, "the board never came back")

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForFocus(app, "tv.menu.playAGame"), "the board's menu has Play a game focused")
        Thread.sleep(forTimeInterval: 0.6)
        shot("menu")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(el(app, "tv.poster.board").waitForExistence(timeout: Live.t(10)), "home has no board poster")
        Thread.sleep(forTimeInterval: 1)
        shot("home")

        // Back to the board from its poster, then Unlink: home again, and the poster shows the link.
        XCTAssertTrue(waitForFocus(app, "tv.poster.cat-tower"))
        press(app, .down, to: "tv.poster.tiles")
        press(app, .down, to: "tv.poster.board")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(el(app, "tv.board").waitForExistence(timeout: Live.t(10)))
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForFocus(app, "tv.menu.playAGame"))
        press(app, .down, to: "tv.menu.sound")
        press(app, .down, to: "tv.menu.unlink")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForFocus(app, "tv.poster.cat-tower", timeout: 10), "Unlink didn't go home")
        press(app, .down, to: "tv.poster.tiles")
        press(app, .down, to: "tv.poster.board")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForFocus(app, "tv.boardLink.back"), "the board's link panel has Back focused")
        Thread.sleep(forTimeInterval: 0.8)
        shot("link")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForFocus(app, "tv.poster.board"), "Menu closes the link panel")
    }
}
