import XCTest

/// The Daily Dish cross-platform check, Apple TV half (apps/play-api/scripts/daily-crosscheck).
/// Skipped unless the runner sets `CROSSCHECK_TV` (`TEST_RUNNER_CROSSCHECK_TV=1`). The TV opens
/// Tonight's board's link panel and waits there; the harness (`api.mjs tv`) links the board by the
/// code the TV asked the server for, turns Show on TV on for each game and plays the plan. This
/// presses Watch on each offer and stays on the run to its end. The proxy records every frame the
/// TV is sent, for comparing with the browser TV's; `TV_SHOTS_DIR` keeps a picture of each run's
/// last frame and its result.
@MainActor
final class DailyCrossCheckTVTests: XCTestCase {
    private let server = ProcessInfo.processInfo.environment["POUNCE_DAILY_SERVER"] ?? "http://127.0.0.1:8819"

    override func setUp() {
        continueAfterFailure = false
    }

    func testWatchEachGameTheHarnessPlays() throws {
        guard ProcessInfo.processInfo.environment["CROSSCHECK_TV"] == "1" else { throw XCTSkip("no CROSSCHECK_TV") }
        let app = XCUIApplication()
        app.launchArguments = Live.arguments() + ["-settings.soundOn", "<false/>", "-tv.soundOn", "<false/>"]
        app.launchEnvironment["POUNCE_API_BASE_URL"] = server
        app.launch()

        // A board kept from an earlier run: unlink it from the TV's menu, so this run links its own.
        if el(app, "tv.board").waitForExistence(timeout: Live.t(4)) {
            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(waitForFocus(app, "tv.menu.playAGame"))
            press(app, .down, to: "tv.menu.sound")
            press(app, .down, to: "tv.menu.unlink")
            XCUIRemote.shared.press(.select)
        }
        XCTAssertTrue(el(app, "tv.poster.board").waitForExistence(timeout: Live.t(20)), "no Tonight's board poster: is DAILY on?")
        XCTAssertTrue(waitForFocus(app, "tv.poster.cat-tower", timeout: 10))
        press(app, .right, to: "tv.poster.tiles")
        press(app, .right, to: "tv.poster.birdwatch")
        press(app, .right, to: "tv.poster.board")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(el(app, "tv.boardLink.code").waitForExistence(timeout: Live.t(15)), "no link code")
        print("CROSSCHECK TV code \(label(el(app, "tv.boardLink.code")) ?? "")")
        XCTAssertTrue(el(app, "tv.board").waitForExistence(timeout: 300), "the harness never linked the board")

        for n in 1...4 {
            XCTAssertTrue(el(app, "tv.watch.card").waitForExistence(timeout: 300), "no watch card for run \(n)")
            XCTAssertTrue(waitForFocus(app, "tv.watch.notNow"))
            press(app, .left, to: "tv.watch.watch")
            XCUIRemote.shared.press(.select)
            let game = ["sniff", "nine-lives", "cat-nap", "box-fort"].first { el(app, "tv.watch.view.\($0)").waitForExistence(timeout: 2) }
            let name = try XCTUnwrap(game, "Watch shows no game's run")
            print("CROSSCHECK TV watching \(name)")
            XCTAssertTrue(el(app, "tv.watch.ended").waitForExistence(timeout: 300), "\(name) never ended on the TV")
            Thread.sleep(forTimeInterval: 1)
            shot("crosscheck-\(name)")
            XCTAssertTrue(until(20) { !self.el(app, "tv.watch.ended").exists && self.el(app, "tv.board").exists }, "no board after \(name)")
        }
        shot("crosscheck-board")
        app.terminate()
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
}
