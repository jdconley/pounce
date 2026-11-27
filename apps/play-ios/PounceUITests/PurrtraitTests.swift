import XCTest

/// Purrtrait on a phone, on its demo socket (`-demo purr-*`, no server), driven by the taps and
/// strokes a person makes: a word picked, lines drawn, Undo, Got it and who said it, the reveal;
/// Give up; a guesser's phone that says look at the TV and "You draw next"; a shared phone's
/// curtain before the words; the lobby's timer; and screenshots of each screen
/// (`TEST_RUNNER_PURR_SHOTS_DIR`).
@MainActor
final class PurrtraitTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func probe(_ app: XCUIApplication) -> [String: String] {
        var out: [String: String] = [:]
        for part in (value(el(app, "purr.debug")) ?? "").split(separator: " ") {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 { out[pair[0]] = pair[1] }
        }
        return out
    }

    private func launch(_ demo: String, extra: [String] = []) -> XCUIApplication {
        let app = Live.demo(demo)
        app.launchArguments += ["-settings.soundOn", "<false/>"] + extra
        app.launch()
        return app
    }

    /// A finger across the easel, from one share of it to another.
    private func stroke(_ easel: XCUIElement, from: CGVector, to: CGVector) {
        let a = easel.coordinate(withNormalizedOffset: from)
        let b = easel.coordinate(withNormalizedOffset: to)
        a.press(forDuration: 0.05, thenDragTo: b, withVelocity: .fast, thenHoldForDuration: 0.05)
    }

    func testAWordFromPickToReveal() {
        let app = launch("purr-pick")
        let tricky = el(app, "purr.pick.tricky")
        XCTAssertTrue(tricky.waitForExistence(timeout: Live.t(10)), "no word cards")
        XCTAssertTrue(el(app, "purr.pick.easy").exists)
        tricky.tap()
        let easel = el(app, "purr.easel")
        XCTAssertTrue(easel.waitForExistence(timeout: Live.t(5)), "no easel after the pick: \(probe(app))")
        XCTAssertEqual(el(app, "purr.word").label, "Draw sandcastle")
        stroke(easel, from: CGVector(dx: 0.2, dy: 0.2), to: CGVector(dx: 0.8, dy: 0.6))
        el(app, "purr.color.4").tap()
        el(app, "purr.width.2").tap()
        stroke(easel, from: CGVector(dx: 0.2, dy: 0.8), to: CGVector(dx: 0.8, dy: 0.8))
        XCTAssertTrue(until(3) { self.probe(app)["strokes"] == "2" }, "two strokes: \(probe(app))")
        el(app, "purr.undo").tap()
        XCTAssertTrue(until(3) { self.probe(app)["strokes"] == "1" }, "undo: \(probe(app))")

        el(app, "purr.gotIt").tap()
        let kiki = el(app, "purr.guesser.2")
        XCTAssertTrue(kiki.waitForExistence(timeout: Live.t(5)), "no Got it sheet")
        XCTAssertFalse(el(app, "purr.guesser.0").exists, "the drawer can't have guessed")
        kiki.tap()
        let word = el(app, "purr.reveal.word")
        XCTAssertTrue(word.waitForExistence(timeout: Live.t(5)), "no reveal: \(probe(app))")
        XCTAssertTrue(until(3) { self.probe(app)["scores"]?.hasPrefix("5,1,4") == true }, "Tricky scores 2 each: \(probe(app))")
    }

    func testGiveUpRevealsWithNoPoints() {
        let app = launch("purr-draw")
        let give = el(app, "purr.giveUp")
        XCTAssertTrue(give.waitForExistence(timeout: Live.t(10)), "no Give up")
        give.tap()
        let confirm = app.alerts.buttons.matching(identifier: "purr.giveUp.confirm").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: Live.t(3)), "Give up asks first")
        confirm.tap()
        XCTAssertTrue(el(app, "purr.reveal.word").waitForExistence(timeout: Live.t(5)), "no reveal")
        XCTAssertTrue(until(3) { self.probe(app)["scores"]?.hasPrefix("3,1,2") == true }, "nobody scores: \(probe(app))")
    }

    func testAGuesserLooksAtTheTV() {
        let app = launch("purr-watch")
        XCTAssertTrue(el(app, "purr.look").waitForExistence(timeout: Live.t(10)), "no Look at the TV")
        XCTAssertFalse(el(app, "purr.easel").exists, "a guesser has no easel")
        XCTAssertFalse(el(app, "purr.word").exists, "a guesser has no word")
        XCTAssertEqual(el(app, "purr.turn").label, "Leo is drawing")
        XCTAssertFalse(el(app, "purr.next").exists)
        app.terminate()

        let next = launch("purr-next")
        XCTAssertTrue(el(next, "purr.next").waitForExistence(timeout: Live.t(10)), "no You draw next")
    }

    func testASharedPhoneHidesTheWordsBehindTheCurtain() {
        let app = launch("purr-curtain")
        XCTAssertTrue(el(app, "screen-curtain").waitForExistence(timeout: Live.t(10)), "no curtain")
        XCTAssertFalse(el(app, "purr.pick.easy").isHittable, "the words show under the curtain")
        let hold = el(app, "curtain.hold")
        hold.press(forDuration: 1.2)
        XCTAssertTrue(el(app, "purr.pick.easy").waitForExistence(timeout: Live.t(5)), "no words after the hold")
    }

    func testTheHostPicksTheTimer() {
        let app = launch("purr-lobby")
        let ninety = el(app, "purr.timer.90")
        XCTAssertTrue(ninety.waitForExistence(timeout: Live.t(10)), "no timer pills")
        ninety.tap()
        XCTAssertTrue(until(3) { ninety.isSelected }, "90 isn't picked")
        XCTAssertTrue(el(app, "lobby.start").exists)
        XCTAssertFalse(el(app, "lobby.code").exists, "a Purrtrait lobby shares no code")
    }

    // MARK: screenshots

    /// Every screen, saved under `TEST_RUNNER_PURR_SHOTS_DIR` as `<prefix>-<name>.png` (prefix from
    /// `TEST_RUNNER_PURR_SHOTS_PREFIX`), with `-demo-long-names`. Skipped without a folder.
    func testScreenshots() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["PURR_SHOTS_DIR"] ?? env["TEST_RUNNER_PURR_SHOTS_DIR"] else { throw XCTSkip("no shots folder") }
        let prefix = env["PURR_SHOTS_PREFIX"] ?? env["TEST_RUNNER_PURR_SHOTS_PREFIX"] ?? "shot"
        let long = (env["PURR_SHOTS_LONG"] ?? env["TEST_RUNNER_PURR_SHOTS_LONG"]) == "1" ? ["-demo-long-names"] : []
        let shots: [(String, String, String, (XCUIApplication) -> Void)] = [
            ("pick", "purr-pick", "purr.pick.easy", { _ in }),
            ("draw", "purr-draw", "purr.easel", { app in
                let easel = self.el(app, "purr.easel")
                self.stroke(easel, from: CGVector(dx: 0.25, dy: 0.3), to: CGVector(dx: 0.75, dy: 0.3))
                self.el(app, "purr.color.1").tap()
                self.stroke(easel, from: CGVector(dx: 0.3, dy: 0.7), to: CGVector(dx: 0.7, dy: 0.5))
            }),
            ("gotit", "purr-crowd", "purr.gotIt", { app in self.el(app, "purr.gotIt").tap() }),
            ("watch", "purr-watch", "purr.look", { _ in }),
            ("next", "purr-next", "purr.next", { _ in }),
            ("paused", "purr-paused", "purr.look", { _ in }),
            ("reveal", "purr-reveal", "purr.reveal.word", { _ in }),
            ("missed", "purr-missed", "purr.reveal.word", { _ in }),
            ("over", "purr-over", "purr.over.title", { _ in }),
            ("curtain", "purr-curtain", "screen-curtain", { _ in }),
            ("lobby", "purr-lobby", "purr.timer.60", { _ in }),
        ]
        let landscape = (env["PURR_SHOTS_ORIENTATION"] ?? env["TEST_RUNNER_PURR_SHOTS_ORIENTATION"]) == "landscape"
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        for (name, demo, ready, act) in shots {
            let app = launch(demo, extra: long)
            XCTAssertTrue(el(app, ready).waitForExistence(timeout: Live.t(10)), "\(name): never ready")
            act(app)
            Thread.sleep(forTimeInterval: 1.2)
            let shot = XCUIScreen.main.screenshot()
            try shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(prefix)-\(name).png"))
            app.terminate()
        }
    }
}
