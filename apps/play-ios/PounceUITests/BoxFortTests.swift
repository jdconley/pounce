import XCTest

/// Box Fort end to end against a dev server with `DAILY=on` (G2 uses its own,
/// `wrangler dev --port 8803 --var DAILY:on --var DAILY_TEST:on`; point the runner at it with
/// `TEST_RUNNER_POUNCE_API_BASE_URL`). The test reads the board from the DEBUG `boxfort.state`
/// element and drags pieces onto the rug the way a finger does, greedily, until the run ends.
/// Skipped when the server has no Box Fort.
@MainActor
final class BoxFortTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The board as the play view reports it.
    struct Board {
        var rug: [Int]
        var x: Double
        var y: Double
        var cell: Double
        var pieces: [[(r: Int, c: Int)]]
        var placed: [Bool]
        var ready: Bool

        init?(_ value: String?) {
            guard let value else { return nil }
            var f: [String: String] = [:]
            for part in value.split(separator: "|") {
                let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 { f[kv[0]] = kv[1] }
            }
            guard let rug = f["rug"], rug.count == 64, let x = f["x"].flatMap(Double.init), let y = f["y"].flatMap(Double.init),
                  let cell = f["cell"].flatMap(Double.init), let pieces = f["pieces"], let placed = f["placed"]
            else { return nil }
            self.rug = rug.compactMap { $0.wholeNumberValue }
            self.x = x
            self.y = y
            self.cell = cell
            self.pieces = pieces.split(separator: "/", omittingEmptySubsequences: false).map { piece in
                piece.split(separator: " ").compactMap { pair in
                    let d = pair.compactMap(\.wholeNumberValue)
                    return d.count == 2 ? (d[0], d[1]) : nil
                }
            }
            self.placed = placed.map { $0 == "1" }
            ready = f["ready"] == "1"
        }

        func fits(_ cells: [(r: Int, c: Int)], _ row: Int, _ col: Int) -> Bool {
            cells.allSatisfy { r, c in
                let y = row + r, x = col + c
                return y >= 0 && y < 8 && x >= 0 && x < 8 && rug[y * 8 + x] == 0
            }
        }

        /// Of the pieces left, the placement that clears the most lines (top-left first).
        func greedy() -> (slot: Int, row: Int, col: Int)? {
            var best: (slot: Int, row: Int, col: Int, lines: Int)?
            for (slot, cells) in pieces.enumerated() where slot < placed.count && !placed[slot] && !cells.isEmpty {
                for row in 0..<8 {
                    for col in 0..<8 where fits(cells, row, col) {
                        var next = rug
                        for (r, c) in cells { next[(row + r) * 8 + col + c] = 1 }
                        let rows = (0..<8).filter { y in (0..<8).allSatisfy { next[y * 8 + $0] != 0 } }.count
                        let cols = (0..<8).filter { x in (0..<8).allSatisfy { next[$0 * 8 + x] != 0 } }.count
                        if best == nil || rows + cols > best!.lines { best = (slot, row, col, rows + cols) }
                    }
                }
            }
            return best.map { ($0.slot, $0.row, $0.col) }
        }
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = Live.app()
        app.launchArguments += ["-seed-people"] + extra
        app.launch()
        return app
    }

    /// Opens today's Box Fort from Home, or skips when this server has none.
    private func open(_ app: XCUIApplication) throws {
        XCTAssertTrue(el(app, "screen-home").waitForExistence(timeout: Live.t(20)), "no Home")
        let treat = el(app, "home.dish.box-fort")
        if !treat.waitForExistence(timeout: Live.t(20)) {
            throw XCTSkip("the server at \(Live.baseURL) has no Box Fort (DAILY on?)")
        }
        treat.tap()
        XCTAssertTrue(el(app, "screen-daily").waitForExistence(timeout: Live.t(10)), "no puzzle screen")
        XCTAssertTrue(el(app, "boxfort.state").waitForExistence(timeout: Live.t(15)), "Box Fort never came up")
    }

    private func board(_ app: XCUIApplication) -> (Board, CGPoint)? {
        let state = el(app, "boxfort.state")
        guard let snap = try? state.snapshot(), let b = Board(snap.value as? String) else { return nil }
        return (b, snap.frame.origin)
    }

    /// A screen point as a coordinate.
    private func at(_ app: XCUIApplication, _ p: CGPoint) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: p.x, dy: p.y))
    }

    /// Where the finger lets go for the piece's top-left to land on (`row`, `col`): the play view
    /// floats a held piece 1.1 spots above the finger, centered across it (`BoxFortLayout.lifted`).
    private func drop(_ b: Board, origin: CGPoint, cells: [(r: Int, c: Int)], row: Int, col: Int) -> CGPoint {
        let rows = Double((cells.map(\.r).max() ?? 0) + 1)
        let cols = Double((cells.map(\.c).max() ?? 0) + 1)
        return CGPoint(
            x: origin.x + b.x + (Double(col) + cols / 2) * b.cell,
            y: origin.y + b.y + (Double(row) + rows + 1.1) * b.cell)
    }

    private func slotCenter(_ app: XCUIApplication, _ slot: Int) -> CGPoint {
        let f = el(app, "boxfort.slot.\(slot)").frame
        return CGPoint(x: f.midX, y: f.midY)
    }

    /// Places the best piece left, the way a finger does. False once the run has ended.
    @discardableResult
    private func placeOne(_ app: XCUIApplication, _ n: Int) -> Bool {
        guard until(10, { self.board(app)?.0.ready == true || self.el(app, "daily.end").exists }) else {
            XCTFail("the board never got ready after \(n) placements")
            return false
        }
        if el(app, "daily.end").exists { return false }
        guard let (b, origin) = board(app), let move = b.greedy() else {
            // Nothing fits: the server ends the run.
            XCTAssertTrue(el(app, "daily.end").waitForExistence(timeout: Live.t(15)), "stuck, and the run never ended")
            return false
        }
        let points = value(el(app, "boxfort.points")) ?? "0"
        let from = at(app, slotCenter(app, move.slot))
        let to = at(app, drop(b, origin: origin, cells: b.pieces[move.slot], row: move.row, col: move.col))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .fast, thenHoldForDuration: 0.1)
        XCTAssertTrue(until(5) { (self.value(self.el(app, "boxfort.points")) ?? "0") != points || self.el(app, "daily.end").exists },
                      "placement \(n + 1) (\(move)) didn't land")
        return true
    }

    func testBoxFortPlaysToTheEnd() throws {
        let app = launch()
        try open(app)
        XCTAssertTrue(el(app, "daily.clock").exists, "no clock")
        var placements = 0
        while placeOne(app, placements) {
            placements += 1
            XCTAssertLessThan(placements, 120, "the run never ended")
        }
        XCTAssertTrue(el(app, "daily.end").waitForExistence(timeout: Live.t(15)), "the run never ended")
        XCTAssertEqual(el(app, "daily.end.headline").label, "Fort built")
        XCTAssertTrue(el(app, "daily.end.result").label.contains("points"), "no points: \(el(app, "daily.end.result").label)")
        XCTAssertGreaterThan(placements, 2)
    }

    /// Screenshots of Box Fort for the pull request, against the dev server: a fresh board, a board
    /// a few pieces in, and the end, at the normal and the biggest text size (an iPad in both
    /// orientations). Skipped unless the runner sets `BOXFORT_SHOTS_DIR`.
    func testShots() throws {
        let env = ProcessInfo.processInfo.environment["BOXFORT_SHOTS_DIR"] ?? ""
        guard !env.isEmpty else { throw XCTSkip("no BOXFORT_SHOTS_DIR") }
        let pad = UIDevice.current.userInterfaceIdiom == .pad
        let big = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        func save(_ name: String) {
            let suffix = pad ? (XCUIDevice.shared.orientation.isLandscape ? "-landscape" : "-portrait") : ""
            try? FileManager.default.createDirectory(atPath: env, withIntermediateDirectories: true)
            try? XCUIScreen.main.screenshot().pngRepresentation
                .write(to: URL(fileURLWithPath: env).appendingPathComponent("\(name)\(suffix).png"))
        }
        for orientation in pad ? [UIDeviceOrientation.portrait, .landscapeLeft] : [.portrait] {
            XCUIDevice.shared.orientation = orientation
            for large in pad ? [false] : [false, true] {
                let prefix = large ? "big-text-" : ""
                let app = XCUIApplication()
                app.launchArguments = Live.arguments(speed: 4) + ["-uitest-reset", "-seed-people"] + (large ? big : [])
                app.launchEnvironment["POUNCE_API_BASE_URL"] = Live.baseURL
                app.launch()
                XCTAssertTrue(el(app, "screen-home").waitForExistence(timeout: Live.t(20)), "no Home")
                Thread.sleep(forTimeInterval: 2)
                save(prefix + "home")
                try open(app)
                Thread.sleep(forTimeInterval: 1.5)
                save(prefix + "boxfort-start")
                var n = 0
                while n < 5, placeOne(app, n) { n += 1 }
                Thread.sleep(forTimeInterval: 1.5)
                save(prefix + "boxfort-playing")
                while placeOne(app, n) { n += 1 }
                XCTAssertTrue(el(app, "daily.end.place").waitForExistence(timeout: Live.t(15)))
                Thread.sleep(forTimeInterval: 2)
                save(prefix + "boxfort-end")
                app.terminate()
            }
        }
        XCUIDevice.shared.orientation = .portrait
    }

    /// The drag holds the frame budget (`docs/main-thread.md`): pieces lifted and carried slowly
    /// across the rug (the landing spot and the lines it would clear changing under them), then let
    /// go above it so they fly home. Nothing reads the screen while the drags run. Prints a
    /// `FRAMES boxfort-drag` line and fails like `DailyFrameTests`.
    func testTheDragHoldsTheFrameRate() throws {
        let app = XCUIApplication()
        app.launchArguments = Live.arguments(speed: 1) + ["-uitest-reset", "-seed-people"]
        app.launchEnvironment["POUNCE_API_BASE_URL"] = Live.baseURL
        app.launch()
        try open(app)
        guard let (b, origin) = board(app) else { return XCTFail("no board") }
        let slots = (0..<3).filter { !b.placed[$0] }.map { slotCenter(app, $0) }
        // From the tray up across the whole rug to just above it: the piece floats over every row
        // (its landing spot and the lines it would clear change all the way), then lets go above
        // the rug, where nothing lands, and flies home.
        let above = origin.y + b.y - 0.5 * b.cell
        let path = [1.0, 7.0, 4.0].map { CGPoint(x: origin.x + b.x + $0 * b.cell, y: above) }
        let before = gameplayBaseline(app)
        let started = Date()
        var i = 0
        while Date().timeIntervalSince(started) < 12 {
            let slot = slots[i % slots.count]
            let via = path[i % path.count]
            at(app, slot).press(forDuration: 0.1, thenDragTo: at(app, via), withVelocity: .slow, thenHoldForDuration: 0)
            i += 1
        }
        let host = Host.framesUnreliable()
        guard let after = watchdog(app) else { return XCTFail("the watchdog went away") }
        let window = after - before
        let report = window.report("boxfort-drag") + String(format: " | host load %.2f per core | %d drags", host.load, i)
        print(report)
        let note = XCTAttachment(string: report)
        note.name = "frames-boxfort-drag"
        note.lifetime = .keepAlways
        add(note)
        XCTAssertGreaterThan(window.link.count, 12 * 20, "the screen hardly drew: \(report)")
        for failure in window.timeFailures() { XCTFail("\(failure): \(report)") }
        if host.busy || !window.nearReference {
            print("FRAMES boxfort-drag: frames over 16.7 ms are reported, not enforced (\(host.busy ? "busy Mac" : "slow machine"))")
        } else {
            XCTAssertEqual(window.link.slow, 0, "the main thread missed a frame by over 16.7 ms: \(report)")
        }
        // Nothing landed: the drags all ended off the rug.
        XCTAssertEqual(board(app)?.0.placed, b.placed, "a drag off the rug placed a piece")
    }
}
