import XCTest

/// Plays the scripted turns the How to play videos are cut from (`HowTo/make.sh` records the
/// simulator while these run, then cuts and captions the footage). Every tap and drag is a real
/// one on a demo table (`-demo howto`, `celebrate`, `tiles-early`, `tiles`, `tiles-last`), at
/// normal speed, with `-show-touches` drawing a ring under the finger.
///
/// Each beat's start goes to the log in the runner's `POUNCE_HOWTO_LOG` (one JSON object per
/// line: `{"t": <unix seconds>, "seg": "...", "beat": "..."}`; `"beat": "-start"` and `"-end"`
/// bracket each segment), which the script lines up with the recording. The beat ids are the
/// ones in `HowTo/beats.json`, which holds each beat's caption. Skipped without the log, so the
/// ordinary UI suite never runs it.
@MainActor
final class HowToVideoTests: XCTestCase {
    nonisolated(unsafe) private var log: FileHandle?
    private var segment = ""

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard let path = ProcessInfo.processInfo.environment["POUNCE_HOWTO_LOG"] else {
            throw XCTSkip("records the How to play videos (run through HowTo/make.sh)")
        }
        if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
        log = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        log?.seekToEndOfFile()
    }

    /// XCUITest's idle waits off for the run (the table never looks idle while it animates, and
    /// each wait would stall the animation being recorded).
    private func noIdleWaits() {
        let restore = Quiescence.disable()
        addTeardownBlock { restore() }
    }

    // MARK: Cat Tower

    func testCatTower() throws {
        noIdleWaits()
        let app = open("howto", segment: "cattower-turn")
        guard let start = untilSnap(app, 30, every: 0.5, { $0.debug.map { $0.settled && $0.step == "draw" } ?? false }) else {
            return XCTFail("the table never came up")
        }
        mark("-start")
        hold(1.5)

        mark("goal")
        if let tower = start.frame("table.tower") { tap(app, tower) }
        hold(4.2)

        mark("level")
        // Any touch folds the tower; the trays show this round's level.
        hold(3.6)

        mark("draw")
        guard let deck = UISnap(app)?.frame("table.deck") else { return XCTFail("no deck") }
        tap(app, deck)
        XCTAssertNotNil(untilSnap(app, 10, every: 0.5) { $0.debug.map { $0.step == "play" && $0.settled } ?? false }, "the draw never landed")
        hold(1.6)

        mark("trays")
        for (card, tray) in [("9, tabby", 0), ("9, gray", 0), ("9, calico", 0), ("4, tuxedo", 1), ("5, gray", 1), ("6, calico", 1)] {
            guard let snap = UISnap(app), let i = handIndex(snap, card), let from = snap.frame("table.hand.\(i)"),
                  let to = snap.frame("table.tray.\(tray)") else { return XCTFail("\(card) is not in the hand") }
            tap(app, CGRect(x: from.minX, y: from.minY, width: min(from.width, 30), height: from.height))
            hold(0.35)
            tap(app, to)
            hold(0.6)
        }
        hold(0.8)

        mark("yarn")
        guard let snap = UISnap(app), let yarn = handIndex(snap, "Yarn, wild"), let card = snap.frame("table.hand.\(yarn)"),
              let last = snap.frame("table.traycard.1.2"), let tray = snap.frame("table.tray.1") else { return XCTFail("no Yarn") }
        drag(app, from: CGPoint(x: card.minX + min(card.width, 24) / 2, y: card.midY + 10),
             to: CGPoint(x: last.maxX + last.width * 0.4, y: tray.midY))
        hold(2.4)

        mark("laydown")
        guard let paw = UISnap(app)?.frame("table.laydown") else { return XCTFail("no lay-down paw") }
        tap(app, paw)
        XCTAssertNotNil(untilSnap(app, 10, every: 0.5) { $0.debug?.laid == true && $0.debug?.settled == true }, "never laid down")
        hold(2.2)

        mark("hit")
        guard let s2 = UISnap(app), let eight = handIndex(s2, "8, gray"), let c8 = s2.frame("table.hand.\(eight)"),
              let run = s2.frame("table.group.1.1") else { return XCTFail("no 8 or no run to hit") }
        drag(app, from: CGPoint(x: c8.minX + min(c8.width, 24) / 2, y: c8.midY + 10), to: CGPoint(x: run.maxX - 6, y: run.midY))
        hold(2.6)

        mark("discard")
        guard let s3 = UISnap(app), let cuke = handIndex(s3, "Cucumber"), let cc = s3.frame("table.hand.\(cuke)") else {
            return XCTFail("no Cucumber")
        }
        tap(app, CGRect(x: cc.minX, y: cc.minY, width: min(cc.width, 30), height: cc.height))
        hold(2.4)

        mark("cucumber")
        guard let leo = UISnap(app)?.frame("table.opponent.1") else { return XCTFail("no Leo") }
        tap(app, leo)
        hold(4.5)
        mark("others")
        _ = untilSnap(app, 15, every: 0.5) { $0.value("table.turn") == "mine" }
        hold(1.0)
        mark("-end")
        app.terminate()

        // The end of a round and of the game, as the celebrate demo plays them.
        let party = open("celebrate", segment: "cattower-end")
        _ = untilSnap(party, 30, every: 0.5) { $0.debug != nil }
        mark("-start")
        _ = untilSnap(party, 40, every: 0.4) { $0.debug?.status == "roundOver" }
        // The demo's script is fixed (CelebrateSocket.gaps), so after the round ends the beats
        // follow at set times: the points, the climb, the next deal.
        mark("roundover")
        hold(1.6)
        mark("score")
        hold(2.2)
        mark("climb")
        hold(2.6)
        mark("lastround")
        _ = untilSnap(party, 40, every: 0.4) { $0.debug?.status == "gameOver" || $0.debug == nil }
        mark("win")
        hold(11)
        mark("-end")
        party.terminate()
    }

    // MARK: the tile game

    func testTiles() throws {
        noIdleWaits()
        // The opening, a draw.
        let app = open("tiles-early", segment: "tiles-open")
        XCTAssertTrue(el(app, "tiles.debug").waitForExistence(timeout: 30))
        hold(1.0)
        mark("-start")
        hold(1.0)
        mark("goal")
        hold(3.4)

        mark("match")
        tapPieces(app, ["5, mouse", "5, fish", "5, feather"])
        newSet(app)
        hold(1.8)

        mark("opening")
        hold(3.2)

        mark("row")
        tapPieces(app, ["10, fish", "11, fish", "12, fish"])
        newSet(app)
        hold(2.2)

        mark("play")
        guard let play = UISnap(app)?.frame("tiles.turn") else { return XCTFail("no turn button") }
        tap(app, play)
        hold(2.4)
        mark("others")
        XCTAssertTrue(until(30) { self.probe(app)["turn"] == "draw" }, "the move never came back")
        hold(0.8)

        mark("draw")
        if let button = UISnap(app)?.frame("tiles.turn") {
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: button.midX, dy: button.midY)).press(forDuration: 1.0)
        }
        hold(3.0)
        mark("-end")
        app.terminate()

        // Adding, Yarn, rearranging.
        let mid = open("tiles", segment: "tiles-mid")
        XCTAssertTrue(el(mid, "tiles.debug").waitForExistence(timeout: 30))
        hold(1.0)
        mark("-start")
        hold(0.6)
        mark("add")
        guard let s = UISnap(mid), let seven = rackFrame(s, "7, fish"), let fishRow = setFrame(s, "Row, fish, 3 to 6") else {
            return XCTFail("no fish 7 or fish row")
        }
        drag(mid, from: CGPoint(x: seven.midX, y: seven.midY), to: CGPoint(x: fishRow.midX, y: fishRow.minY + fishRow.height * 0.6))
        hold(2.4)

        mark("yarn")
        tapPieces(mid, ["7, bell"])
        guard let bells = UISnap(mid).flatMap({ setFrame($0, "Row, bell, 5 to 8") }) else { return XCTFail("no bell row") }
        tap(mid, bells)
        hold(3.4)

        mark("rearrange")
        tapPieces(mid, ["13, fish", "13, mouse"])
        newSet(mid)
        hold(1.6)
        guard let row = UISnap(mid).flatMap({ setFrame($0, "Row, bell, 5 to 9") }) else { return XCTFail("no bell row 5 to 9") }
        tap(mid, row)
        hold(1.4)
        guard let s4 = UISnap(mid), let yarn = s4.items.first(where: { $0.key.hasPrefix("tiles.loupe.") && $0.value.label.hasPrefix("Yarn") })?.value.frame,
              let thirteens = setFrame(s4, "Not a set yet") else { return XCTFail("no Yarn in the loupe or no new set") }
        drag(mid, from: CGPoint(x: yarn.midX, y: yarn.midY), to: CGPoint(x: thirteens.midX, y: thirteens.minY + thirteens.height * 0.6))
        hold(2.6)

        mark("play2")
        if let close = UISnap(mid)?.frame("tiles.loupe.close") {
            tap(mid, close)
            hold(0.8)
        }
        if let play = UISnap(mid)?.frame("tiles.turn") { tap(mid, play) }
        hold(2.4)
        mark("-end")
        mid.terminate()

        // Going out.
        let last = open("tiles-last", segment: "tiles-win")
        XCTAssertTrue(el(last, "tiles.debug").waitForExistence(timeout: 30))
        hold(1.0)
        mark("-start")
        hold(0.6)
        mark("last")
        for (piece, target) in [("7, fish", "Row, fish, 3 to 6"), ("13, mouse", "Row, mouse, 10 to 12"), ("11, feather", "Row, feather, 8 to 10")] {
            guard let s = UISnap(last), let from = rackFrame(s, piece), let to = setFrame(s, target) else {
                return XCTFail("no \(piece) or no \(target)")
            }
            tap(last, from)
            hold(0.4)
            tap(last, to)
            hold(0.8)
        }
        hold(0.6)
        mark("win")
        if let play = UISnap(last)?.frame("tiles.turn") { tap(last, play) }
        XCTAssertTrue(el(last, "screen-tiles-over").waitForExistence(timeout: 15), "no game over")
        hold(5.5)
        mark("-end")
        last.terminate()
    }

    // MARK: helpers

    /// The demo at normal speed with touch rings, and the segment the log's next beats belong to.
    private func open(_ demo: String, segment: String) -> XCUIApplication {
        self.segment = segment
        let app = XCUIApplication()
        app.launchArguments = ["-anim-speed", "1", "-uitest-reset", "-seed-people", "-show-touches", "-timecode", "-demo", demo]
        if let cast = ProcessInfo.processInfo.environment["POUNCE_DEMO_CAST"] { app.launchEnvironment["POUNCE_DEMO_CAST"] = cast }
        app.launch()
        return app
    }

    private func mark(_ beat: String) {
        let line = String(format: "{\"t\": %.3f, \"seg\": \"%@\", \"beat\": \"%@\"}\n", Date().timeIntervalSince1970, segment, beat)
        log?.write(Data(line.utf8))
        print("[howto] \(segment) \(beat)")
    }

    private func hold(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func drag(_ app: XCUIApplication, from: CGPoint, to: CGPoint) {
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: from.x, dy: from.y))
            .press(forDuration: 0.25, thenDragTo: origin.withOffset(CGVector(dx: to.x, dy: to.y)), withVelocity: 420, thenHoldForDuration: 0.35)
    }

    private func handIndex(_ snap: UISnap, _ card: String) -> Int? {
        var i = 0
        while let l = snap.label("table.hand.\(i)") {
            if l.hasPrefix(card) { return i }
            i += 1
        }
        return nil
    }

    private func rackFrame(_ snap: UISnap, _ piece: String) -> CGRect? {
        snap.items.first { $0.key.hasPrefix("tiles.rack.") && $0.value.label == piece }?.value.frame
    }

    private func setFrame(_ snap: UISnap, _ label: String) -> CGRect? {
        snap.items.first { $0.key.hasPrefix("tiles.set.") && $0.value.label.hasPrefix(label) }?.value.frame
    }

    private func tapPieces(_ app: XCUIApplication, _ pieces: [String]) {
        for piece in pieces {
            guard let frame = UISnap(app).flatMap({ rackFrame($0, piece) }) else { return XCTFail("no stash piece \(piece)") }
            tap(app, frame)
            hold(0.5)
        }
    }

    private func newSet(_ app: XCUIApplication) {
        guard let slot = UISnap(app)?.frame("tiles.newset") else { return XCTFail("no new-set slot") }
        tap(app, slot)
    }

    private func probe(_ app: XCUIApplication) -> [String: String] {
        var out: [String: String] = [:]
        for part in (value(el(app, "tiles.debug")) ?? "").split(separator: " ") {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 { out[pair[0]] = pair[1] }
        }
        return out
    }
}
