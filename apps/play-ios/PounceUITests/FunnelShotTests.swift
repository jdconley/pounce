import XCTest

/// Screenshots of the first-run funnel for a design review, written as PNGs to `FUNNEL_SHOT_DIR`
/// (`TEST_RUNNER_FUNNEL_SHOT_DIR` for xcodebuild) with names starting `FUNNEL_SHOT_PREFIX`.
/// The invite walk needs a room code in `FUNNEL_CODE`. Skipped without a directory.
@MainActor
final class FunnelShotTests: XCTestCase {
    private var dir: URL?
    private var prefix = "funnel"
    private var step = 0

    override func setUpWithError() throws {
        continueAfterFailure = true
        let env = ProcessInfo.processInfo.environment
        guard let path = env["FUNNEL_SHOT_DIR"], !path.isEmpty else { throw XCTSkip("FUNNEL_SHOT_DIR not set") }
        dir = URL(fileURLWithPath: path, isDirectory: true)
        prefix = env["FUNNEL_SHOT_PREFIX"] ?? prefix
        try FileManager.default.createDirectory(at: dir!, withIntermediateDirectories: true)
    }

    private func save(_ name: String, settle: TimeInterval = 1.2) {
        guard let dir else { return }
        Thread.sleep(forTimeInterval: settle)
        step += 1
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: dir.appendingPathComponent(String(format: "%@-%02d-%@.png", prefix, step, name)))
    }

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = Live.arguments() + ["-uitest-reset", "-age-range", "declined", "-tips", "-ui-tips", "-house-cat"]
            + extra
        app.launchEnvironment["POUNCE_API_BASE_URL"] = Live.baseURL
        app.launch()
        return app
    }

    private func age(_ app: XCUIApplication, prefix: String) {
        XCTAssertTrue(el(app, "age.confirm").waitForExistence(timeout: Live.t(15)), "no age keypad")
        save("\(prefix)-age")
        for d in "1985" { el(app, "age.key.\(d)").tap() }
        el(app, "age.confirm").tap()
        XCTAssertTrue(el(app, "age.yes").waitForExistence(timeout: Live.t(5)))
        save("\(prefix)-age-confirm")
        el(app, "age.yes").tap()
        XCTAssertTrue(el(app, "screen-pickCat").waitForExistence(timeout: Live.t(10)), "no pick-a-cat")
        // An invited guest's line comes from a peek at the table.
        _ = el(app, "pickcat.invite").waitForExistence(timeout: prefix == "invited" ? Live.t(8) : 0.5)
        save("\(prefix)-pickcat")
        let name = el(app, "pickcat.name")
        name.tap()
        name.typeText("Mia")
        save("\(prefix)-pickcat-typed")
        name.typeText("\n")
        _ = until(4) { app.keyboards.count == 0 }
        save("\(prefix)-pickcat-done", settle: 0.5)
        el(app, "pickcat.confirm").tap()
    }

    func testNewPlayer() {
        let app = launch([])
        age(app, prefix: "new")
        XCTAssertTrue(el(app, "screen-home").waitForExistence(timeout: Live.t(15)), "no Home")
        save("new-home", settle: 2.5)
        // One tip on the first visit: dismissed, no other follows.
        let tip = app.descendants(matching: .any).matching(identifier: "tip").firstMatch
        if tip.waitForExistence(timeout: 2) {
            tip.tap()
            save("new-home-after-tip", settle: 3.5)
        }
        el(app, "home.newGame").tap()
        _ = el(app, "lobby.seat.0").waitForExistence(timeout: Live.t(20))
        save("new-lobby", settle: 2.5)
        let qr = el(app, "lobby.qr")
        if qr.exists {
            qr.tap()
            save("new-lobby-same-room", settle: 1.5)
            qr.tap()
        }
        el(app, "lobby.home").tap()
        XCTAssertTrue(el(app, "screen-home").waitForExistence(timeout: Live.t(10)))
        let practice = el(app, "home.practice")
        if practice.waitForExistence(timeout: 5) {
            practice.tap()
            save("new-practice-connecting", settle: 0.6)
            save("new-practice-table", settle: 5)
            for i in 0..<4 {
                let ok = el(app, "coach.ok")
                guard ok.waitForExistence(timeout: 8) else { break }
                save("new-coach\(i + 1)", settle: 0.5)
                ok.tap()
            }
            save("new-after-coach", settle: 2)
        }
    }

    func testInvitedPlayer() throws {
        guard let code = ProcessInfo.processInfo.environment["FUNNEL_CODE"], !code.isEmpty else {
            throw XCTSkip("FUNNEL_CODE not set")
        }
        let app = launch(["-open-link", "pounce-dev://j/\(code)"])
        age(app, prefix: "invited")
        save("invited-after-pickcat", settle: 1)
        save("invited-lobby", settle: 5)
    }
}
