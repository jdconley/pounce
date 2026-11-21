import XCTest

/// Sniff end to end against a dev server with `DAILY=on` (G3 uses its own, `wrangler dev --port
/// 8804`; point the runner at it with `TEST_RUNNER_POUNCE_API_BASE_URL`): Home's treat, the
/// puzzle, guesses marked by the server, and the end. Each test is a new person, so each plays
/// today's Sniff fresh. Skipped when the server has the Dish off.
/// Sound off while testing: nothing plays out loud on the machine running the tests. A plist false,
/// since `Settings` reads the value as a Bool and a bare "NO" reads as text (so, sound on).
private let muted = ["-settings.soundOn", "<false/>"]

@MainActor
final class SniffTests: XCTestCase {
    /// Six allowed words with different letters. Today's answer is secret, so a run ends solved if
    /// one of them is it, and missed otherwise.
    private static let words = ["crane", "sloth", "pudgy", "witch", "femur", "balky"]
    private static let marks = ["right spot", "elsewhere", "not in the word"]

    override func setUp() {
        continueAfterFailure = false
    }

    /// A new person's app on today's Sniff. `realTime`: animations at their real speed (a note on
    /// screen for its real 1.4 s), not the tests' faster pace.
    private func open(realTime: Bool = false) throws -> XCUIApplication {
        let app = Live.app()
        if realTime { app.launchArguments = Live.arguments(speed: 1) + ["-uitest-reset"] }
        app.launchArguments += ["-seed-people"] + muted
        app.launch()
        XCTAssertTrue(el(app, "screen-home").waitForExistence(timeout: Live.t(20)), "no Home")
        let treat = el(app, "home.dish.sniff")
        guard treat.waitForExistence(timeout: Live.t(20)) else {
            throw XCTSkip("the server at \(Live.baseURL) has no Dish or no Sniff (DAILY on?)")
        }
        treat.tap()
        XCTAssertTrue(el(app, "screen-daily").waitForExistence(timeout: Live.t(10)), "no puzzle screen")
        XCTAssertTrue(el(app, "sniff.key.a").waitForExistence(timeout: Live.t(15)), "Sniff never came up")
        return app
    }

    private func type(_ app: XCUIApplication, _ word: String) {
        for letter in word { el(app, "sniff.key.\(letter)").tap() }
        el(app, "sniff.send").tap()
    }

    /// How many of row `row`'s tags carry a mark (its label lists each tag's letter and mark).
    private func marked(_ app: XCUIApplication, row: Int) -> Int {
        let element = el(app, "sniff.row.\(row)")
        guard element.exists else { return 0 }
        let label = element.label
        return Self.marks.reduce(0) { $0 + label.components(separatedBy: $1).count - 1 }
    }

    func testSniffPlaysToTheEnd() throws {
        let app = try open()
        var solved = false
        for (row, word) in Self.words.enumerated() {
            type(app, word)
            // The guess that ends the run brings up the end screen over the board.
            let last = row == Self.words.count - 1
            XCTAssertTrue(
                until(10) { self.marked(app, row: row) == 5 || (last && self.el(app, "daily.end").exists) },
                "\(word) never came back marked")
            if !el(app, "daily.end").exists, el(app, "sniff.row.\(row)").label.components(separatedBy: "right spot").count - 1 == 5 {
                solved = true
            }
            if el(app, "daily.end").exists { break }
        }
        XCTAssertTrue(el(app, "daily.end").waitForExistence(timeout: Live.t(15)), "the run never ended")
        let headline = el(app, "daily.end.headline").label
        XCTAssertTrue(["Solved", "Missed"].contains(headline), "ended as \(headline)")
        if solved { XCTAssertEqual(headline, "Solved") }
        XCTAssertTrue(el(app, "daily.end.share").waitForExistence(timeout: Live.t(10)), "no share")
    }

    func testAnUnknownWordShakesAndIsNeverSent() throws {
        let app = try open(realTime: true)
        type(app, "zzzzz")
        XCTAssertTrue(el(app, "sniff.note").waitForExistence(timeout: Live.t(5)), "no note for an unknown word")
        XCTAssertEqual(el(app, "sniff.note").label, "Not a word")
        XCTAssertEqual(marked(app, row: 0), 0, "an unknown word was marked")
        XCTAssertTrue(el(app, "sniff.row.0").label.hasPrefix("Z"), "the row isn't still typed: \(el(app, "sniff.row.0").label)")
        // The row is still typed: delete it and send a real word.
        for _ in 0..<5 { el(app, "sniff.delete").tap() }
        type(app, "crane")
        XCTAssertTrue(until(10) { self.marked(app, row: 0) == 5 }, "crane never came back marked")
    }
}

/// Frame times on Sniff's screen (`docs/main-thread.md`), as `DailyFrameTests` measures the host:
/// today's Sniff open on a dev server with `DAILY=on`, two guesses in and a word half typed, the
/// clock running. Prints a `FRAMES` line, and fails on a main-thread hang over 100 ms or app work
/// over 8.3 ms in a frame, and, near the reference's speed on a quiet machine, a frame over 16.7 ms.
@MainActor
final class SniffFrameTests: XCTestCase {
    private let seconds: Double = ProcessInfo.processInfo.environment["POUNCE_FRAMES_SECONDS"].flatMap(Double.init) ?? 12

    override func setUp() {
        continueAfterFailure = true
    }

    func testSniffHoldsTheFrameRate() throws {
        let app = XCUIApplication()
        app.launchArguments = Live.arguments(speed: 1) + ["-uitest-reset", "-seed-people"] + muted
        app.launchEnvironment["POUNCE_API_BASE_URL"] = Live.baseURL
        app.launch()
        let treat = el(app, "home.dish.sniff")
        guard treat.waitForExistence(timeout: Live.t(25)) else { throw XCTSkip("no Sniff on \(Live.baseURL)") }
        treat.tap()
        XCTAssertTrue(el(app, "sniff.key.a").waitForExistence(timeout: Live.t(15)), "Sniff never came up")
        for word in ["crane", "sloth"] {
            for letter in word { el(app, "sniff.key.\(letter)").tap() }
            el(app, "sniff.send").tap()
        }
        for letter in "pud" { el(app, "sniff.key.\(letter)").tap() }
        let before = gameplayBaseline(app)
        // Only waiting: nothing reads the screen in the window.
        Thread.sleep(forTimeInterval: seconds)
        let host = Host.framesUnreliable()
        guard let after = watchdog(app) else { return XCTFail("the watchdog went away") }
        let window = after - before
        let report = window.report("daily-sniff") + String(format: " | host load %.2f per core", host.load)
        print(report)
        let note = XCTAttachment(string: report)
        note.name = "frames-daily-sniff"
        note.lifetime = .keepAlways
        add(note)
        XCTAssertGreaterThan(window.link.count, Int(seconds) * 20, "the screen hardly drew: \(report)")
        for failure in window.timeFailures() { XCTFail("\(failure): \(report)") }
        if host.busy || !window.nearReference {
            print("FRAMES daily-sniff: frames over 16.7 ms are reported, not enforced (\(host.busy ? "busy Mac" : "slow machine"))")
        } else {
            XCTAssertEqual(window.link.slow, 0, "the main thread missed a frame by over 16.7 ms: \(report)")
        }
    }
}

/// Screenshots of every screen Sniff touches (`AGENTS.md`), against a dev server with `DAILY=on`:
/// Home and the Dish (where Sniff's treat and card now show), and Sniff itself: new, two guesses in
/// with a word half typed, an unknown word, and the end. Skipped unless the runner sets
/// `SNIFF_SHOTS_DIR` (`TEST_RUNNER_SNIFF_SHOTS_DIR`); `SNIFF_SHOTS_ONLY_SHELL=1` takes Home and the
/// Dish alone (the "before" set, from a build without Sniff listed). An iPad takes each in portrait
/// and landscape; an iPhone also takes the largest text size.
@MainActor
final class SniffShotTests: XCTestCase {
    private static let big = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private var dir: String? { env["SNIFF_SHOTS_DIR"].flatMap { $0.isEmpty ? nil : $0 } }
    private var pad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    override func setUp() {
        continueAfterFailure = true
    }

    private func save(_ name: String) {
        guard let dir else { return }
        let suffix = pad ? (XCUIDevice.shared.orientation.isLandscape ? "-landscape" : "-portrait") : ""
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name)\(suffix).png"))
    }

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = Live.arguments(speed: 1) + ["-uitest-reset", "-seed-people"] + muted + extra
        app.launchEnvironment["POUNCE_API_BASE_URL"] = Live.baseURL
        app.launch()
        return app
    }

    private func play(_ app: XCUIApplication, _ word: String, send: Bool = true) {
        for letter in word { el(app, "sniff.key.\(letter)").tap() }
        if send { el(app, "sniff.send").tap() }
    }

    func testShots() throws {
        guard dir != nil else { throw XCTSkip("no SNIFF_SHOTS_DIR") }
        let shellOnly = env["SNIFF_SHOTS_ONLY_SHELL"] == "1"
        for orientation in pad ? [UIDeviceOrientation.portrait, .landscapeLeft] : [.portrait] {
            XCUIDevice.shared.orientation = orientation
            for big in pad ? [false] : [false, true] {
                let text = big ? Self.big : []
                let prefix = big ? "big-text-" : ""

                var app = launch(text)
                XCTAssertTrue(el(app, "screen-home").waitForExistence(timeout: Live.t(20)), "no Home")
                Thread.sleep(forTimeInterval: 3)
                save("\(prefix)home")
                app.terminate()

                app = launch(text + ["-show-dish"])
                XCTAssertTrue(el(app, "screen-dish").waitForExistence(timeout: Live.t(20)), "no Dish")
                Thread.sleep(forTimeInterval: 3)
                save("\(prefix)dish")
                app.terminate()
                if shellOnly { continue }

                app = launch(text)
                let treat = el(app, "home.dish.sniff")
                guard treat.waitForExistence(timeout: Live.t(25)) else { throw XCTSkip("no Sniff on \(Live.baseURL)") }
                treat.tap()
                XCTAssertTrue(el(app, "sniff.key.a").waitForExistence(timeout: Live.t(15)), "Sniff never came up")
                Thread.sleep(forTimeInterval: 1.5)
                save("\(prefix)sniff-new")
                play(app, "crane")
                Thread.sleep(forTimeInterval: 1.2)
                play(app, "sloth")
                Thread.sleep(forTimeInterval: 1.2)
                play(app, "pud", send: false)
                Thread.sleep(forTimeInterval: 1)
                save("\(prefix)sniff-mid")
                for _ in 0..<3 { el(app, "sniff.delete").tap() }
                play(app, "zzzzz")
                Thread.sleep(forTimeInterval: 0.5)
                save("\(prefix)sniff-not-a-word")
                for _ in 0..<5 { el(app, "sniff.delete").tap() }
                for word in ["pudgy", "witch", "femur", "balky"] where !el(app, "daily.end").exists {
                    play(app, word)
                    Thread.sleep(forTimeInterval: 1.2)
                }
                XCTAssertTrue(el(app, "daily.end").waitForExistence(timeout: Live.t(15)), "the run never ended")
                Thread.sleep(forTimeInterval: 2.5)
                save("\(prefix)sniff-end")
                app.terminate()
            }
        }
        XCUIDevice.shared.orientation = .portrait
    }
}
