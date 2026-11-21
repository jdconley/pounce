import XCTest

/// The Daily Dish cross-platform check, iPhone half. Skipped unless the runner sets `CROSSCHECK_PLAN`
/// (`TEST_RUNNER_CROSSCHECK_PLAN`) to a plan the harness wrote from the server's secret and the date: for
/// each game, one fixed move list. Each test plays its game's list through the app's own controls,
/// paced past the game's floor, and the harness compares what the server answered with the
/// browser's run of the same list.
@MainActor
final class DailyCrossCheckTests: XCTestCase {
    struct Plan: Decodable {
        let game: String
        let paceMs: Double
        let moves: [Move]
    }

    struct Move: Decodable {
        let k: String
        let i: Int?, d: Int?
        let cells: [Int]?
        let word: String?
        let slot: Int?, row: Int?, col: Int?
    }

    override func setUp() {
        continueAfterFailure = false
    }

    private func plan(_ game: String) throws -> Plan {
        guard let path = ProcessInfo.processInfo.environment["CROSSCHECK_PLAN"], !path.isEmpty else { throw XCTSkip("no CROSSCHECK_PLAN") }
        struct File: Decodable { let plans: [Plan] }
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        return try XCTUnwrap(file.plans.first { $0.game == game })
    }

    /// A new person's app on today's `game`, and when its run started.
    private func open(_ game: String, ready: String) throws -> (XCUIApplication, Date) {
        let app = Live.app()
        app.launchArguments += ["-seed-people", "-settings.soundOn", "<false/>"]
        app.launch()
        XCTAssertTrue(el(app, "screen-home").waitForExistence(timeout: Live.t(20)), "no Home")
        let treat = el(app, "home.dish.\(game)")
        guard treat.waitForExistence(timeout: Live.t(20)) else { throw XCTSkip("no \(game) on \(Live.baseURL)") }
        treat.tap()
        XCTAssertTrue(el(app, ready).waitForExistence(timeout: Live.t(15)), "\(game) never came up")
        return (app, Date())
    }

    /// Waits until move `k` is due: the plan's pace from the start.
    private func pace(_ t0: Date, _ k: Int, _ gapMs: Double) {
        let wait = t0.addingTimeInterval(gapMs * Double(k + 1) / 1000).timeIntervalSinceNow
        if wait > 0 { Thread.sleep(forTimeInterval: wait) }
    }

    private func finish(_ app: XCUIApplication) {
        XCTAssertTrue(el(app, "daily.end").waitForExistence(timeout: Live.t(20)), "the run never ended")
        print("CROSSCHECK END \(el(app, "daily.end.headline").label)")
        Thread.sleep(forTimeInterval: 1.5)
    }

    func testNineLives() throws {
        let p = try plan("nine-lives")
        let (app, t0) = try open("nine-lives", ready: "nine-lives-cell-80")
        for (k, m) in p.moves.enumerated() {
            pace(t0, k, p.paceMs)
            el(app, "nine-lives-cell-\(m.i!)").tap()
            el(app, "nine-lives-key-\(m.d!)").tap()
        }
        finish(app)
    }

    func testCatNap() throws {
        let p = try plan("cat-nap")
        let (app, t0) = try open("cat-nap", ready: "catnap.quilt")
        for (k, m) in p.moves.enumerated() {
            pace(t0, k, p.paceMs)
            el(app, "catnap.cell.\(m.cells![0])").tap()
        }
        finish(app)
    }

    func testSniff() throws {
        let p = try plan("sniff")
        let (app, t0) = try open("sniff", ready: "sniff.key.a")
        for (k, m) in p.moves.enumerated() {
            pace(t0, k, p.paceMs)
            for letter in m.word! { el(app, "sniff.key.\(letter)").tap() }
            el(app, "sniff.send").tap()
            let last = k == p.moves.count - 1
            XCTAssertTrue(until(10) {
                if last && self.el(app, "daily.end").exists { return true }
                let row = self.el(app, "sniff.row.\(k)")
                guard row.exists else { return false }
                let label = row.label
                let marks = ["right spot", "elsewhere", "not in the word"].reduce(0) { $0 + label.components(separatedBy: $1).count - 1 }
                return marks == 5 || (last && self.el(app, "daily.end").exists)
            }, "\(m.word!) never came back marked")
        }
        finish(app)
    }

    /// Box Fort's DEBUG `boxfort.state`: the rug's origin and cell size, the pieces, and readiness.
    private func boxFort(_ app: XCUIApplication) -> (x: Double, y: Double, cell: Double, pieces: [[(Int, Int)]], placed: [Bool], ready: Bool, origin: CGPoint)? {
        guard let snap = try? el(app, "boxfort.state").snapshot(), let value = snap.value as? String else { return nil }
        var f: [String: String] = [:]
        for part in value.split(separator: "|") {
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { f[kv[0]] = kv[1] }
        }
        guard let x = f["x"].flatMap(Double.init), let y = f["y"].flatMap(Double.init), let cell = f["cell"].flatMap(Double.init),
              let pieces = f["pieces"], let placed = f["placed"] else { return nil }
        let cells = pieces.split(separator: "/", omittingEmptySubsequences: false).map { piece in
            piece.split(separator: " ").compactMap { pair -> (Int, Int)? in
                let d = pair.compactMap(\.wholeNumberValue)
                return d.count == 2 ? (d[0], d[1]) : nil
            }
        }
        return (x, y, cell, cells, placed.map { $0 == "1" }, f["ready"] == "1", snap.frame.origin)
    }

    func testBoxFort() throws {
        let p = try plan("box-fort")
        let (app, t0) = try open("box-fort", ready: "boxfort.state")
        let screen = app.coordinate(withNormalizedOffset: .zero)
        for (k, m) in p.moves.enumerated() {
            pace(t0, k, p.paceMs)
            XCTAssertTrue(until(10) { self.boxFort(app)?.ready == true }, "the board never got ready for move \(k)")
            let b = try XCTUnwrap(boxFort(app))
            let cells = b.pieces[m.slot!]
            let rows = Double((cells.map(\.0).max() ?? 0) + 1), cols = Double((cells.map(\.1).max() ?? 0) + 1)
            let to = CGPoint(x: b.origin.x + b.x + (Double(m.col!) + cols / 2) * b.cell,
                             y: b.origin.y + b.y + (Double(m.row!) + rows + 1.1) * b.cell)
            let slot = el(app, "boxfort.slot.\(m.slot!)").frame
            let from = screen.withOffset(CGVector(dx: slot.midX, dy: slot.midY))
            from.press(forDuration: 0.05, thenDragTo: screen.withOffset(CGVector(dx: to.x, dy: to.y)), withVelocity: .fast, thenHoldForDuration: 0.1)
            XCTAssertTrue(until(5) {
                guard let now = self.boxFort(app) else { return self.el(app, "daily.end").exists }
                return now.placed[m.slot!] || !now.ready || self.el(app, "daily.end").exists || now.placed.allSatisfy { !$0 }
            }, "move \(k) didn't land")
        }
        finish(app)
    }
}
