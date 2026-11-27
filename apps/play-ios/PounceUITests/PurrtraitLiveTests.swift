import XCTest

/// Purrtrait on a live table (the combined run, docs/superpowers/plans/2026-11-26-purrtrait-ios-tv.md):
/// this phone joins a TV's table from the link in `$POUNCE_SHARED_DIR/purr-link.txt` (the TV's QR,
/// `pounce-dev://e/<CODE>?near=<KEY>`), and plays to game over with whoever else sits there. On
/// its own turns it picks the Easy word, draws two strokes, and taps Got it for the first other
/// player. It leaves `ios-drew-<turn>` in the shared folder as it draws and screenshots there.
///
/// Skipped unless `POUNCE_SHARED_DIR` is set (`TEST_RUNNER_POUNCE_SHARED_DIR`), with the server in
/// `TEST_RUNNER_POUNCE_API_BASE_URL`.
@MainActor
final class PurrtraitLiveTests: XCTestCase {
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

    private func stroke(_ easel: XCUIElement, from: CGVector, to: CGVector) {
        easel.coordinate(withNormalizedOffset: from)
            .press(forDuration: 0.05, thenDragTo: easel.coordinate(withNormalizedOffset: to), withVelocity: .slow, thenHoldForDuration: 0.05)
    }

    private func save(_ app: XCUIApplication, _ shared: String, _ name: String) {
        screenshot(app, name)
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(shared)/\(name).png"))
    }

    func testPlaysATVsTableToGameOver() throws {
        guard let shared = ProcessInfo.processInfo.environment["POUNCE_SHARED_DIR"] else {
            throw XCTSkip("a live run: set POUNCE_SHARED_DIR and write the TV's link to purr-link.txt")
        }
        // Not `-uitest-reset`: `app.open(url)` relaunches the app, and must find the same player.
        let app = XCUIApplication()
        app.launchArguments = Live.arguments() + ["-no-tips", "-settings.soundOn", "<false/>"]
        app.launchEnvironment["POUNCE_API_BASE_URL"] = Live.baseURL
        app.launch()
        // A fresh app names its player first; a busy simulator takes a while to get there.
        XCTAssertTrue(until(60) { self.el(app, "pickcat.confirm").exists || self.el(app, "home.newGame").exists }, "no first run or Home")
        if el(app, "pickcat.confirm").exists { onboard(app) }
        try? FileManager.default.removeItem(atPath: "\(shared)/purr-link.txt")
        FileManager.default.createFile(atPath: "\(shared)/ios-ready", contents: Data())
        var link = ""
        XCTAssertTrue(until(600) {
            link = ((try? String(contentsOfFile: "\(shared)/purr-link.txt", encoding: .utf8)) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return !link.isEmpty
        }, "no link in purr-link.txt")
        app.open(URL(string: link)!)
        let open = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Open"]
        if open.waitForExistence(timeout: Live.t(5)) { open.tap() }
        // The lobby (the TV's link sits this phone down), or the game already going.
        XCTAssertTrue(until(30) { self.el(app, "screen-lobby").exists || self.el(app, "purr.debug").exists || self.el(app, "pickcat.confirm").exists },
                      "the TV's link didn't open its table")
        if el(app, "pickcat.confirm").exists {
            el(app, "pickcat.dice").tap()
            el(app, "pickcat.confirm").tap()
            XCTAssertTrue(until(30) { self.el(app, "screen-lobby").exists || self.el(app, "purr.debug").exists }, "no table after naming")
        }
        if el(app, "lobby.sit").waitForExistence(timeout: Live.t(3)) { el(app, "lobby.sit").tap() }
        save(app, shared, "ios-lobby")
        FileManager.default.createFile(atPath: "\(shared)/ios-seated", contents: Data())

        var drew = Set<String>()
        var shotsTaken = Set<String>()
        let finished = until(1500) {
            if self.el(app, "purr.over.title").exists { return true }
            let p = self.probe(app)
            let turn = p["turn"] ?? ""
            if p["screen"] == "reveal", !shotsTaken.contains("reveal-\(turn)") {
                shotsTaken.insert("reveal-\(turn)")
                self.save(app, shared, "ios-reveal-\(turn.replacingOccurrences(of: ":", with: "-"))")
            }
            let easy = self.el(app, "purr.pick.easy")
            if easy.exists, easy.isHittable {
                easy.tap()
                return false
            }
            let easel = self.el(app, "purr.easel")
            if easel.exists, !turn.isEmpty, !drew.contains(turn) {
                drew.insert(turn)
                Thread.sleep(forTimeInterval: 0.8)  // past the easel's settle
                self.stroke(easel, from: CGVector(dx: 0.25, dy: 0.3), to: CGVector(dx: 0.75, dy: 0.35))
                self.stroke(easel, from: CGVector(dx: 0.3, dy: 0.7), to: CGVector(dx: 0.7, dy: 0.55))
                let tag = turn.replacingOccurrences(of: ":", with: "-")
                FileManager.default.createFile(atPath: "\(shared)/ios-drew-\(tag)", contents: Data())
                self.save(app, shared, "ios-drawing-\(tag)")
                Thread.sleep(forTimeInterval: 4)  // the TV shows it; the run takes its picture
                self.el(app, "purr.gotIt").tap()
                let guesser = app.descendants(matching: .any)
                    .matching(NSPredicate(format: "identifier BEGINSWITH 'purr.guesser.'")).firstMatch
                if guesser.waitForExistence(timeout: Live.t(5)) { guesser.tap() }
            }
            return false
        }
        save(app, shared, "ios-over")
        XCTAssertTrue(finished, "no game over: \(probe(app))")
        XCTAssertFalse(drew.isEmpty, "this phone never drew")
    }
}
