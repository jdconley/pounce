import XCTest

/// Each cat in the top bar wears two numbers: its phase on a gold "L4" chip at the bottom left
/// (with the laid-down sticker once this round's phase is down) and its card count on a mini
/// card back at the bottom right. The DEBUG probe `table.badges` says what each cat's chips show
/// ("seat=phase chip/card count"); VoiceOver reads both in each `table.opponent.<seat>` label.
@MainActor
final class PhaseBadgeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ demo: String) -> XCUIApplication {
        let app = Live.demo(demo)
        app.launch()
        // A fresh simulator has no push answer yet, so a table puts the priming screen up.
        if el(app, "priming.notNow").waitForExistence(timeout: Live.t(4)) { dismissPriming(app) }
        _ = until(5) { !self.el(app, "priming.notNow").exists }
        return app
    }

    private func badges(_ app: XCUIApplication) -> [String: String] {
        let raw = value(el(app, "table.badges")) ?? ""
        var out: [String: String] = [:]
        for part in raw.split(separator: ",") {
            let pair = part.split(separator: "=", maxSplits: 1)
            if pair.count == 2 { out[String(pair[0])] = String(pair[1]) }
        }
        return out
    }

    /// `-demo table`: Leo (1) laid phase 1 down and holds 4 cards, Kiki (2) is on phase 7 and
    /// the House Cat (3) on phase 4, both with 10 cards. I'm on phase 3: the folded tower says so.
    func testEveryCatWearsItsPhaseAndCardCount() {
        let app = launch("table")
        XCTAssertTrue(el(app, "table.badges").waitForExistence(timeout: Live.t(10)), "no badge probe")
        XCTAssertTrue(until(5) { self.badges(app).count == 4 }, "badges \(self.badges(app))")
        let shown = badges(app)
        XCTAssertEqual(shown["1"], "L1+laid/4")
        XCTAssertEqual(shown["2"], "L7/10")
        XCTAssertEqual(shown["3"], "L4/10")
        XCTAssertEqual(shown["tab"], "L3")

        let leo = label(el(app, "table.opponent.1")) ?? "-"
        XCTAssertTrue(leo.hasPrefix("Leo, 4 cards, level 1, laid down"), leo)
        let kiki = label(el(app, "table.opponent.2")) ?? "-"
        XCTAssertTrue(kiki.hasPrefix("Kiki, 10 cards, level 7"), kiki)
        XCTAssertFalse(kiki.contains("laid down"), kiki)
        screenshot(app, "phase-badges")
    }

    /// `-demo celebrate`: Kiki goes out finishing phase 3 (her chip moves on to P4 with the
    /// next deal), then I go out finishing phase 10 and Leo moves on to P2. The folded tower
    /// wears my phase on the same chip: a trophy once all 10 are done.
    func testChipsMoveOnAfterARound() {
        let app = launch("celebrate")
        XCTAssertTrue(el(app, "gameover.home").waitForExistence(timeout: Live.t(45)), "no game over")
        let shown = badges(app)
        XCTAssertEqual(shown["1"]?.hasPrefix("L2"), true, "\(shown)")
        XCTAssertEqual(shown["2"]?.hasPrefix("L4"), true, "\(shown)")
        XCTAssertEqual(shown["3"]?.hasPrefix("L1"), true, "\(shown)")
        XCTAssertFalse(shown.values.contains { $0.contains("+laid") }, "a laid sticker left over: \(shown)")
        XCTAssertEqual(shown["tab"], "done", "the tab should wear a trophy: \(shown)")
        screenshot(app, "phase-badges-game-over")
    }
}
