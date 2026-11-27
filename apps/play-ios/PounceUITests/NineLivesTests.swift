import XCTest

/// Nine Lives end to end against a dev server with `DAILY=on` (G1 uses its own, `wrangler dev
/// --port 8802`; point the runner at it with `TEST_RUNNER_POUNCE_API_BASE_URL`), on the lives rules
/// (docs/daily-protocol.md, "## Nine Lives"). The app never has the solution, so the test reads
/// today's givens off the screen in one snapshot and solves them itself, then plays. Each test
/// starts a fresh player (`-uitest-reset`), so each gets the day's run new. Skipped when the server
/// has the Dish off.
@MainActor
final class NineLivesTests: XCTestCase {
    /// No sound out loud on the Mac running the tests (a bare "NO" would be read as a string).
    static let quiet = ["-settings.soundOn", "<false/>"]

    private let seconds: Double = ProcessInfo.processInfo.environment["POUNCE_FRAMES_SECONDS"].flatMap(Double.init) ?? 12

    override func setUp() {
        continueAfterFailure = false
    }

    /// Home, then today's Nine Lives; or a skip when this server has no Dish.
    private func open(_ app: XCUIApplication) throws {
        XCTAssertTrue(el(app, "screen-home").waitForExistence(timeout: Live.t(20)), "no Home")
        let treat = el(app, "home.dish.nine-lives")
        guard treat.waitForExistence(timeout: Live.t(20)) else {
            throw XCTSkip("the server at \(Live.baseURL) has no Nine Lives (DAILY on?)")
        }
        treat.tap()
        XCTAssertTrue(el(app, "screen-daily").waitForExistence(timeout: Live.t(10)), "no puzzle screen")
        XCTAssertTrue(el(app, "nine-lives-cell-80").waitForExistence(timeout: Live.t(15)), "the grid never came up")
    }

    /// `speed`: the app's pace (`Pace`); 1 to see the board's last word at its real length.
    private func launch(speed: Double? = nil) throws -> XCUIApplication {
        let app = Live.app()
        if let speed { app.launchArguments = Live.arguments(speed: speed) + ["-uitest-reset"] }
        app.launchArguments += ["-seed-people"] + Self.quiet
        app.launch()
        try open(app)
        return app
    }

    /// Every cell's digit (0: empty), read in one snapshot of the screen.
    private func cells(_ app: XCUIApplication) throws -> (digits: [Int], values: [String]) {
        var digits = [Int](repeating: -1, count: 81)
        var values = [String](repeating: "", count: 81)
        func walk(_ s: any XCUIElementSnapshot) {
            if s.identifier.hasPrefix("nine-lives-cell-"), let i = Int(s.identifier.dropFirst("nine-lives-cell-".count)) {
                let value = s.value as? String ?? ""
                values[i] = value
                // A wrong number shown, or the solution shown, isn't the board's.
                digits[i] = value.hasSuffix("wrong") || value.hasSuffix("answer") ? 0 : Int(value.prefix { $0.isNumber }) ?? 0
            }
            s.children.forEach(walk)
        }
        walk(try app.snapshot())
        XCTAssertFalse(digits.contains(-1), "a cell is missing from the screen")
        return (digits, values)
    }

    /// A digit that isn't `cell`'s answer, whose key is still awake.
    private func wrongDigit(_ cell: Int, _ board: [Int], _ solution: [Int]) -> Int {
        (1...9).first { d in d != solution[cell] && board.filter { $0 == d }.count < 9 }!
    }

    private func lives(_ app: XCUIApplication) -> String? { value(el(app, "nine-lives-lives")) }

    /// Plays `digit` in `cell` and waits for the server's verdict to show.
    private func enter(_ app: XCUIApplication, _ cell: Int, _ digit: Int, wrong: Bool, file: StaticString = #filePath, line: UInt = #line) {
        el(app, "nine-lives-cell-\(cell)").tap()
        el(app, "nine-lives-key-\(digit)").tap()
        let shown = until(10) {
            let v = self.value(self.el(app, "nine-lives-cell-\(cell)")) ?? ""
            return wrong ? v.hasSuffix("wrong") || v.hasSuffix("answer") : v == "\(digit)"
        }
        XCTAssertTrue(shown, "cell \(cell) never showed \(digit) as \(wrong ? "wrong" : "right")", file: file, line: line)
    }

    func testNineLivesPlaysToTheEnd() throws {
        let app = try launch()
        XCTAssertTrue(el(app, "daily.clock").exists, "no clock")
        XCTAssertEqual(lives(app), "3 of 3")
        XCTAssertEqual(value(el(app, "nine-lives-hint")), "3 left")

        let start = try cells(app).digits
        let solution = try XCTUnwrap(GridSolver.solve(start), "today's givens have no solution")

        // A hint fills one open cell with its answer, from the server, and locks it. It costs no life.
        el(app, "nine-lives-hint").tap()
        var hinted = -1
        XCTAssertTrue(until(10) {
            hinted = (try? self.cells(app).values.firstIndex { $0.hasSuffix("hint") }) ?? -1
            return hinted >= 0
        }, "the hint filled nothing")
        let afterHint = try cells(app).digits
        XCTAssertEqual(afterHint[hinted], solution[hinted], "the hint isn't the answer")
        XCTAssertTrue(until(5) { self.value(self.el(app, "nine-lives-hint")) == "2 left" }, "the hint count didn't drop")
        XCTAssertEqual(lives(app), "3 of 3")

        let open = (0..<81).filter { afterHint[$0] == 0 }
        // A wrong number shows red in its cell and costs a life.
        let first = open[0]
        let bad = wrongDigit(first, afterHint, solution)
        enter(app, first, bad, wrong: true)
        XCTAssertTrue(until(5) { self.lives(app) == "2 of 3" }, "no life lost: \(lives(app) ?? "none")")
        // Erase takes it out on the phone; the same wrong number again costs nothing more.
        el(app, "nine-lives-erase").tap()
        XCTAssertTrue(until(5) { self.value(self.el(app, "nine-lives-cell-\(first)")) == "Empty" }, "erase left the wrong number")
        enter(app, first, bad, wrong: true)
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(lives(app), "2 of 3", "the same wrong number cost a second life")

        // Everything else, right: the first cell's right digit replaces the wrong one. A right one locks.
        for (k, i) in open.enumerated() {
            el(app, "nine-lives-cell-\(i)").tap()
            el(app, "nine-lives-key-\(solution[i])").tap()
            if k == 0 {
                XCTAssertTrue(until(5) { self.value(self.el(app, "nine-lives-cell-\(i)")) == "\(solution[i])" }, "no right digit")
                el(app, "nine-lives-erase").tap()
                XCTAssertEqual(value(el(app, "nine-lives-cell-\(i)")), "\(solution[i])", "a right digit was erased")
            }
        }

        XCTAssertTrue(el(app, "daily.end").waitForExistence(timeout: Live.t(15)), "the run never ended")
        XCTAssertEqual(el(app, "daily.end.headline").label, "Solved")
        XCTAssertTrue(el(app, "daily.end.share").exists, "no share")
    }

    /// Three wrong numbers end the run: "Out of lives", the solution fills in, then the end screen.
    func testThreeWrongNumbersFailAndShowTheSolution() throws {
        // At the real pace, so the board's last word (about 2.6 seconds) is long enough to read.
        let app = try launch(speed: 1)
        let start = try cells(app).digits
        let solution = try XCTUnwrap(GridSolver.solve(start))
        let open = (0..<81).filter { start[$0] == 0 }
        for (k, cell) in open.prefix(2).enumerated() {
            enter(app, cell, wrongDigit(cell, start, solution), wrong: true)
            XCTAssertTrue(until(5) { self.lives(app) == "\(2 - k) of 3" }, "lives: \(lives(app) ?? "none")")
        }
        el(app, "nine-lives-cell-\(open[2])").tap()
        el(app, "nine-lives-key-\(wrongDigit(open[2], start, solution))").tap()
        XCTAssertTrue(el(app, "nine-lives-out").waitForExistence(timeout: Live.t(5)), "no Out of lives")
        // The board shows the solution, kindly, before the end screen.
        let shown = try cells(app).values
        let answers = open.filter { shown[$0] == "\(solution[$0]), answer" }
        XCTAssertEqual(answers.count, open.count, "the solution didn't fill in: \(answers.count) of \(open.count)")
        XCTAssertTrue(el(app, "daily.end").waitForExistence(timeout: Live.t(15)), "the run never ended")
        XCTAssertEqual(el(app, "daily.end.headline").label, "Out of lives")
        // How far it got: three wrong numbers and nothing right is 0%.
        XCTAssertEqual(el(app, "daily.end.result").label, "0%")
    }

    /// Three hints a day, none of them costing a life; then the Hint button is spent.
    func testThreeHintsThenTheButtonIsSpent() throws {
        let app = try launch()
        let hint = el(app, "nine-lives-hint")
        for left in [2, 1, 0] {
            hint.tap()
            XCTAssertTrue(until(10) { self.value(hint) == "\(left) left" }, "hints: \(value(hint) ?? "none")")
        }
        XCTAssertEqual(lives(app), "3 of 3")
        XCTAssertEqual(try cells(app).values.filter { $0.hasSuffix("hint") }.count, 3)
        XCTAssertFalse(hint.isEnabled, "the Hint button still works with none left")
        hint.tap()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(try cells(app).values.filter { $0.hasSuffix("hint") }.count, 3, "a fourth hint came")
    }

    /// The clock is active time (spec §3): twenty seconds on the Home Screen mid-puzzle don't
    /// count. The run is given up after it, and the result's time is about the time on screen.
    func testTimeAwayDoesntCount() throws {
        let app = try launch(speed: 1)
        let start = try cells(app).digits
        let solution = try XCTUnwrap(GridSolver.solve(start))
        let cell = try XCTUnwrap((0..<81).first { start[$0] == 0 })
        enter(app, cell, solution[cell], wrong: false)
        let began = Date()
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 20)
        app.activate()
        XCTAssertTrue(el(app, "screen-daily").waitForExistence(timeout: Live.t(10)), "the puzzle didn't come back")
        el(app, "daily.giveup").tap()
        let confirm = app.buttons["daily.giveup.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: Live.t(5)), "no give up confirm")
        confirm.tap()
        XCTAssertTrue(el(app, "daily.end").waitForExistence(timeout: Live.t(15)), "the run never ended")
        let away = Date().timeIntervalSince(began)
        // "Time 0:09": the result's time.
        let label = el(app, "daily.clock").label
        let parts = label.split(separator: " ").last?.split(separator: ":").compactMap { Int($0) } ?? []
        let seconds = parts.reduce(0) { $0 * 60 + $1 }
        XCTAssertGreaterThan(away, 20)
        XCTAssertLessThan(seconds, 15, "the clock counted the time away: \(label) after \(Int(away)) s, 20 of them away")
        XCTAssertGreaterThan(seconds, 0, "no time at all: \(label)")
    }

    /// The Nine Lives screen with its clock running, a few moves in: nothing reads the screen while
    /// it's measured. Fails on a main-thread hang over 100 ms or app work over 8.3 ms in a frame.
    func testNineLivesHoldsTheFrameRate() throws {
        let app = XCUIApplication()
        app.launchArguments = Live.arguments(speed: 1) + ["-uitest-reset", "-seed-people"] + NineLivesTests.quiet
        app.launchEnvironment["POUNCE_API_BASE_URL"] = Live.baseURL
        app.launch()
        try open(app)
        let start = try cells(app).digits
        let solution = try XCTUnwrap(GridSolver.solve(start))
        for i in (0..<81).filter({ start[$0] == 0 }).prefix(4) {
            el(app, "nine-lives-cell-\(i)").tap()
            el(app, "nine-lives-key-\(solution[i])").tap()
        }
        el(app, "nine-lives-notes").tap()

        let before = gameplayBaseline(app)
        Thread.sleep(forTimeInterval: seconds)
        let host = Host.framesUnreliable()
        guard let after = watchdog(app) else { return XCTFail("the watchdog went away") }
        let window = after - before
        let report = window.report("nine-lives") + String(format: " | host load %.2f per core", host.load)
        print(report)
        let note = XCTAttachment(string: report)
        note.name = "frames-nine-lives"
        note.lifetime = .keepAlways
        add(note)
        XCTAssertGreaterThan(window.link.count, Int(seconds) * 20, "the screen hardly drew: \(report)")
        for failure in window.timeFailures() { XCTFail("\(failure): \(report)") }
        if host.busy || !window.nearReference {
            print("FRAMES nine-lives: frames over 16.7 ms are reported, not enforced (\(host.busy ? "busy Mac" : "slow machine"))")
        } else {
            XCTAssertEqual(window.link.slow, 0, "the main thread missed a frame by over 16.7 ms: \(report)")
        }
    }
}

/// Screenshots of every screen Nine Lives touches, for the PR: Home and the Dish with Nine Lives on
/// them (demo data), and against the dev server the puzzle midway (notes, a hint, a wrong number
/// and a life gone), every hint used, out of lives with the solution filling in, and its end.
/// Skipped unless the runner sets `DAILY_SHOTS_DIR`. An iPad takes each in portrait and landscape;
/// a phone also takes the biggest text.
@MainActor
final class NineLivesShotTests: XCTestCase {
    private static let big = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    private var dir: String? {
        let dir = ProcessInfo.processInfo.environment["DAILY_SHOTS_DIR"]
        return dir?.isEmpty == false ? dir : nil
    }

    private var pad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private func save(_ name: String) {
        guard let dir else { return }
        let suffix = pad ? (XCUIDevice.shared.orientation.isLandscape ? "-landscape" : "-portrait") : ""
        // The simulator's name ("G1 SE"), so devices run side by side don't overwrite each other.
        let device = UIDevice.current.name.lowercased().replacingOccurrences(of: " ", with: "-")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(
            to: URL(fileURLWithPath: dir).appendingPathComponent("\(device)-\(name)\(suffix).png"))
    }

    /// `speed` 1 for the puzzle: the board's last word out of lives lasts its real length.
    private func launch(_ args: [String], speed: Double = 4) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = Live.arguments(speed: speed) + ["-uitest-reset", "-seed-people"] + NineLivesTests.quiet + args
        app.launchEnvironment["POUNCE_API_BASE_URL"] = Live.baseURL
        app.launch()
        return app
    }

    func testShots() throws {
        guard dir != nil else { throw XCTSkip("no DAILY_SHOTS_DIR") }
        for orientation in pad ? [UIDeviceOrientation.portrait, .landscapeLeft] : [.portrait] {
            XCUIDevice.shared.orientation = orientation
            for (name, args, screen) in [
                ("home", ["-demo-streaks", "-demo-home", "-demo-dish", "some"], "screen-home"),
                ("dish", ["-demo-streaks", "-demo-dish", "some", "-show-dish"], "screen-dish"),
            ] {
                let app = launch(args)
                XCTAssertTrue(el(app, screen).waitForExistence(timeout: Live.t(15)), "no \(screen)")
                Thread.sleep(forTimeInterval: 2.5)
                save("nine-lives-\(name)")
                app.terminate()
            }
            for big in pad ? [false] : [false, true] {
                try puzzle(big: big)
            }
        }
        XCUIDevice.shared.orientation = .portrait
    }

    /// On a slow network (the runner points at a delaying proxy): a number shows at once as
    /// neutral "checking", never as right, and turns red or locks only on the server's answer.
    /// Also prints how long the answer took to show.
    func testCheckingOnASlowNetwork() throws {
        guard dir != nil else { throw XCTSkip("no DAILY_SHOTS_DIR") }
        let app = launch([], speed: 1)
        XCTAssertTrue(el(app, "screen-home").waitForExistence(timeout: Live.t(30)), "no Home")
        let treat = el(app, "home.dish.nine-lives")
        guard treat.waitForExistence(timeout: Live.t(30)) else { throw XCTSkip("no Nine Lives on \(Live.baseURL)") }
        treat.tap()
        XCTAssertTrue(el(app, "nine-lives-cell-80").waitForExistence(timeout: Live.t(30)), "no grid")
        let givens = try NineLivesBoardReader.digits(app)
        let solution = try XCTUnwrap(GridSolver.solve(givens))
        let open = (0..<81).filter { givens[$0] == 0 }
        for (k, (cell, digit)) in [(open[0], solution[open[0]] % 9 + 1), (open[1], solution[open[1]])].enumerated() {
            let element = el(app, "nine-lives-cell-\(cell)")
            element.tap()
            el(app, "nine-lives-key-\(digit)").tap()
            let tapped = Date()
            let first = value(element) ?? ""
            let checking = first.contains("checking")
            // Whatever the network, a wrong number never shows as a settled digit first.
            if k == 0 { XCTAssertNotEqual(first, "\(digit)", "the wrong number looked right before the answer") }
            if k == 0 { save("nine-lives-slow-checking") }
            // As tight as snapshots allow (each takes a few tens of milliseconds), to time the answer.
            let deadline = Date().addingTimeInterval(Live.t(15))
            var answered = false
            while !answered, Date() < deadline {
                let v = value(element) ?? ""
                answered = k == 0 ? v.hasSuffix("wrong") : v == "\(digit)"
            }
            XCTAssertTrue(answered, "no answer for cell \(cell)")
            let ms = Int(Date().timeIntervalSince(tapped) * 1000)
            print("SLOW \(k == 0 ? "wrong" : "right") shown \(ms) ms after the tap (checking at once: \(checking))")
            // On a slow network it shows as checking at once; on a fast one the answer may beat the look.
            XCTAssertTrue(checking || ms < 200, "neither checking nor answered at once (\(ms) ms)")
            if k == 0 { save("nine-lives-slow-wrong") }
        }
        app.terminate()
    }

    /// Offline mid-puzzle: the runner's server is a proxy that drops off the network on
    /// `/__proxy/off` (`NINE_LIVES_PROXY_CONTROL=1`; the slow-network check in the PR). A number
    /// placed then stays "checking" and the screen says it's reconnecting; it never looks accepted.
    /// Back online, the answer lands.
    func testOfflineNeverLooksAccepted() throws {
        guard dir != nil, ProcessInfo.processInfo.environment["NINE_LIVES_PROXY_CONTROL"] == "1" else {
            throw XCTSkip("no proxy to switch off")
        }
        func network(_ on: Bool) {
            let url = URL(string: "\(Live.baseURL)/__proxy/\(on ? "on" : "off")")!
            let done = expectation(description: "proxy \(on)")
            URLSession.shared.dataTask(with: url) { _, _, _ in done.fulfill() }.resume()
            wait(for: [done], timeout: 5)
        }
        let app = launch([], speed: 1)
        XCTAssertTrue(el(app, "screen-home").waitForExistence(timeout: Live.t(30)), "no Home")
        let treat = el(app, "home.dish.nine-lives")
        guard treat.waitForExistence(timeout: Live.t(30)) else { throw XCTSkip("no Nine Lives on \(Live.baseURL)") }
        treat.tap()
        XCTAssertTrue(el(app, "nine-lives-cell-80").waitForExistence(timeout: Live.t(30)), "no grid")
        let givens = try NineLivesBoardReader.digits(app)
        let solution = try XCTUnwrap(GridSolver.solve(givens))
        let cell = try XCTUnwrap((0..<81).first { givens[$0] == 0 })
        let element = el(app, "nine-lives-cell-\(cell)")
        network(false)
        defer { network(true) }
        element.tap()
        el(app, "nine-lives-key-\(solution[cell] % 9 + 1)").tap()
        XCTAssertTrue(el(app, "daily.reconnecting").waitForExistence(timeout: Live.t(10)), "no Reconnecting")
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue((value(element) ?? "").contains("checking"), "offline, the number looked settled: \(value(element) ?? "")")
        save("nine-lives-offline")
        network(true)
        XCTAssertTrue(until(20) { (self.value(element) ?? "").hasSuffix("wrong") }, "back online, no answer")
        XCTAssertTrue(until(10) { !self.el(app, "daily.reconnecting").exists }, "still reconnecting")
        save("nine-lives-back-online")
        app.terminate()
    }

    /// Today's puzzle against the dev server: midway, hints spent, out of lives, and the end.
    private func puzzle(big: Bool) throws {
        let prefix = big ? "nine-lives-big-text" : "nine-lives"
        let app = launch(big ? Self.big : [], speed: 1)
        XCTAssertTrue(el(app, "screen-home").waitForExistence(timeout: Live.t(20)), "no Home")
        let treat = el(app, "home.dish.nine-lives")
        guard treat.waitForExistence(timeout: Live.t(20)) else { throw XCTSkip("no Nine Lives on \(Live.baseURL)") }
        treat.tap()
        XCTAssertTrue(el(app, "nine-lives-cell-80").waitForExistence(timeout: Live.t(15)), "no grid")
        let givens = try NineLivesBoardReader.digits(app)
        let solution = try XCTUnwrap(GridSolver.solve(givens))
        let open = (0..<81).filter { givens[$0] == 0 }
        let half = open.count / 2
        for i in open.prefix(half) {
            el(app, "nine-lives-cell-\(i)").tap()
            el(app, "nine-lives-key-\(solution[i])").tap()
        }
        el(app, "nine-lives-hint").tap()
        Thread.sleep(forTimeInterval: 1.5)
        // Notes in two cells, then a wrong number, selected.
        let rest = try NineLivesBoardReader.digits(app)
        let free = (0..<81).filter { rest[$0] == 0 }
        el(app, "nine-lives-notes").tap()
        for (cell, notes) in [(free[1], [2, 5, 8]), (free[3], [1, 4])] {
            el(app, "nine-lives-cell-\(cell)").tap()
            for d in notes { el(app, "nine-lives-key-\(d)").tap() }
        }
        el(app, "nine-lives-notes").tap()
        func wrong(_ cell: Int) -> Int { (1...9).first { d in d != solution[cell] && rest.filter { $0 == d }.count < 9 }! }
        el(app, "nine-lives-cell-\(free[0])").tap()
        el(app, "nine-lives-key-\(wrong(free[0]))").tap()
        Thread.sleep(forTimeInterval: 1.5)
        save("\(prefix)-midway")
        // Every hint used, a second life gone.
        el(app, "nine-lives-hint").tap()
        Thread.sleep(forTimeInterval: 1)
        el(app, "nine-lives-hint").tap()
        Thread.sleep(forTimeInterval: 1)
        let later = try NineLivesBoardReader.digits(app)
        let left = (0..<81).filter { later[$0] == 0 && $0 != free[0] }
        el(app, "nine-lives-cell-\(left[2])").tap()
        el(app, "nine-lives-key-\(wrong(left[2]))").tap()
        Thread.sleep(forTimeInterval: 1.5)
        save("\(prefix)-hints-spent")
        // The third: out of lives, and the solution fills in.
        el(app, "nine-lives-cell-\(left[4])").tap()
        el(app, "nine-lives-key-\(wrong(left[4]))").tap()
        XCTAssertTrue(el(app, "nine-lives-out").waitForExistence(timeout: Live.t(5)), "no Out of lives")
        Thread.sleep(forTimeInterval: 1.2)
        save("\(prefix)-out")
        XCTAssertTrue(el(app, "daily.end").waitForExistence(timeout: Live.t(15)), "the run never ended")
        Thread.sleep(forTimeInterval: 2)
        save("\(prefix)-end")
        app.terminate()
    }
}

/// Reads every cell's digit (0: empty) in one snapshot of the screen.
@MainActor
enum NineLivesBoardReader {
    static func digits(_ app: XCUIApplication) throws -> [Int] {
        var digits = [Int](repeating: 0, count: 81)
        func walk(_ s: any XCUIElementSnapshot) {
            if s.identifier.hasPrefix("nine-lives-cell-"), let i = Int(s.identifier.dropFirst("nine-lives-cell-".count)) {
                digits[i] = Int((s.value as? String ?? "").prefix { $0.isNumber }) ?? 0
            }
            s.children.forEach(walk)
        }
        walk(try app.snapshot())
        return digits
    }
}

/// A plain backtracking solver: the test's own, because no client ever gets the solution.
enum GridSolver {
    static func solve(_ givens: [Int]) -> [Int]? {
        var grid = givens
        func fits(_ i: Int, _ d: Int) -> Bool {
            let r = i / 9, c = i % 9, br = r / 3 * 3, bc = c / 3 * 3
            for k in 0..<9 {
                if grid[r * 9 + k] == d || grid[k * 9 + c] == d || grid[(br + k / 3) * 9 + bc + k % 3] == d { return false }
            }
            return true
        }
        func step() -> Bool {
            guard let i = grid.firstIndex(of: 0) else { return true }
            for d in 1...9 where fits(i, d) {
                grid[i] = d
                if step() { return true }
            }
            grid[i] = 0
            return false
        }
        return step() ? grid : nil
    }
}
