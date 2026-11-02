import XCTest

/// A game hosted on a real iPhone against a live server, run by `scripts/phone-game.sh`. The
/// phone can't read a Mac folder or reach the host broker, so the hand-off is one log line: the
/// test prints `[phone] room <CODE>`, the script sees it in xcodebuild's output and starts a
/// `pounce-e2e join <CODE>` remote on the Mac. The phone waits for the remote at seat 1, puts
/// House Cats at seats 2 ..< 2 + `POUNCE_PHONE_BOTS` (default 1), starts, and plays its seat by
/// taps (draw, discard) to the game-over overlay.
final class PhoneGameTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testHostOnPhone() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["POUNCE_PHONE_GAME"] == "1" else {
            throw XCTSkip("run by scripts/phone-game.sh (POUNCE_PHONE_GAME=1)")
        }
        let bots = env["POUNCE_PHONE_BOTS"].flatMap(Int.init) ?? 1
        let restoreQuiescence = Quiescence.disable()
        addTeardownBlock { @MainActor in restoreQuiescence() }
        let app = Live.app()
        app.launch()
        onboard(app)
        newGame(app)
        let code = lobbyCode(app)
        XCTAssertEqual(code.count, 5, "bad room code \(code)")
        print("[phone] room \(code)")

        let seat1 = el(app, "lobby.seat.1")
        XCTAssertTrue(until(300) { seat1.label.contains("on another phone") },
                      "no remote sat at seat 1: \(seat1.label)")
        for seat in 2..<(2 + bots) {
            seatMenu(app, seat: seat, "bot")
            XCTAssertTrue(until(10) { self.el(app, "lobby.seat.\(seat)").label.contains("bot") },
                          "no bot at seat \(seat)")
        }
        screenshot(app, "phone-lobby")
        el(app, "lobby.start").tap()
        print("[phone] started")

        var turns = 0, rounds = Set<Int>()
        let deadline = Date().addingTimeInterval(Live.t(4 * 3600))
        // One whole-app snapshot per poll, every 2 s (see `playTurnByTaps`).
        while Date() < deadline {
            guard let snap = UISnap(app) else {
                Thread.sleep(forTimeInterval: 2)
                continue
            }
            if snap.exists("gameover.home") { break }
            if snap.exists("priming.notNow") {
                dismissPriming(app, snap)
                continue
            }
            if let d = snap.debug, !rounds.contains(d.round) {
                rounds.insert(d.round)
                print("[phone] round \(d.round)")
            }
            if playTurnByTaps(app, snap) {
                turns += 1
            } else {
                Thread.sleep(forTimeInterval: 2)
            }
        }
        XCTAssertTrue(el(app, "gameover.home").waitForExistence(timeout: Live.t(30)),
                      "no game over within the time limit (rounds \(rounds.sorted()))")
        screenshot(app, "phone-gameover")
        print("[phone] game over: \(turns) turns by taps, rounds \(rounds.sorted())")
    }
}
