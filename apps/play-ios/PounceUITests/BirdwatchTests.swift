import XCTest

/// Birdwatch's table on its demo socket (`-demo bird-*`, no server), driven by the taps a person
/// makes: a raise and a bid win the feeder, five cards tapped and Done put them back, a toy names
/// trump, and a card lifted then tapped again is played. Also: a dimmed card refuses, the score
/// sheet opens from the strip, and the five-player partner picker calls a card.
@MainActor
final class BirdwatchTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func probe(_ app: XCUIApplication) -> [String: String] {
        var out: [String: String] = [:]
        for part in (value(el(app, "bird.debug")) ?? "").split(separator: " ") {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 { out[pair[0]] = pair[1] }
        }
        return out
    }

    private func launch(_ demo: String) -> XCUIApplication {
        let app = Live.demo(demo)
        app.launchArguments += ["-settings.soundOn", "<false/>"]
        app.launch()
        XCTAssertTrue(el(app, "screen-birdwatch").waitForExistence(timeout: Live.t(10)), "no Birdwatch table")
        return app
    }

    func testAHandFromBidToPlay() {
        let app = launch("bird-bid")
        let amount = el(app, "bird.bid.amount")
        XCTAssertTrue(amount.waitForExistence(timeout: Live.t(5)), "no bid panel")
        XCTAssertEqual(amount.label, "Bid 80")
        el(app, "bird.bid.raise").tap()
        el(app, "bird.bid.raise").tap()
        XCTAssertTrue(until(3) { amount.label == "Bid 90" }, "raise didn't: \(amount.label)")
        el(app, "bird.bid.send").tap()

        // The feeder's five fish come to my hand: put them back.
        XCTAssertTrue(el(app, "bird.panel.nest").waitForExistence(timeout: Live.t(5)), "no put-back: \(probe(app))")
        for card in [4, 5, 6, 7, 9] {
            let e = el(app, "bird.card.\(card)")
            XCTAssertTrue(e.waitForExistence(timeout: Live.t(3)), "no card \(card)")
            e.tap()
            Thread.sleep(forTimeInterval: Live.pace(0.3))
        }
        XCTAssertTrue(until(3) { (self.el(app, "bird.card.4").label).contains("putting back") }, "card 4 not marked")
        el(app, "bird.nest.done").tap()

        // Trump, then my lead: lift a card and play it.
        let mouse = el(app, "bird.trump.mouse")
        XCTAssertTrue(mouse.waitForExistence(timeout: Live.t(5)), "no trump panel: \(probe(app))")
        mouse.tap()
        XCTAssertTrue(until(5) { self.probe(app)["phase"] == "play" }, "no play: \(probe(app))")
        let before = Int(probe(app)["played"] ?? "0") ?? 0
        let card = el(app, "bird.card.13")
        card.tap()
        Thread.sleep(forTimeInterval: Live.pace(0.3))
        card.tap()
        XCTAssertTrue(until(5) { (Int(self.probe(app)["played"] ?? "0") ?? 0) > before }, "the card never went: \(probe(app))")
    }

    func testADimmedCardRefusesAndTheStripOpensTheScores() {
        let app = launch("bird-play")
        // The 10 of mouse can't follow fish: it says so and stays.
        let dim = el(app, "bird.card.23")
        XCTAssertTrue(dim.waitForExistence(timeout: Live.t(5)))
        XCTAssertTrue(dim.label.contains("can't play"), dim.label)
        dim.tap()
        XCTAssertTrue(el(app, "bird.note").waitForExistence(timeout: Live.t(3)), "no Follow suit note")
        XCTAssertEqual(probe(app)["played"], "11")
        el(app, "bird.scores").tap()
        XCTAssertTrue(el(app, "bird.scores.close").waitForExistence(timeout: Live.t(5)), "no score sheet")
    }

    func testFivePlayersCallAPartner() {
        let app = launch("bird-partner")
        // The picker comes up on its own; calling the 1 of feather starts the play.
        let one = el(app, "bird.partner.28")
        XCTAssertTrue(one.waitForExistence(timeout: Live.t(5)), "no partner picker")
        one.tap()
        XCTAssertTrue(until(5) { self.probe(app)["phase"] == "play" }, "no play after the call: \(probe(app))")
    }

    func testThePartnerMarkWaitsForTheCurtain() {
        // Mine alone: the mark is there.
        let app = launch("bird-partner-mark")
        XCTAssertTrue(el(app, "bird.partner.mark").waitForExistence(timeout: Live.t(5)), "no partner mark on my own hand")
        app.terminate()
        // Two seats on one phone: nothing of the hand, and no mark, before the hold.
        let curtain = launch("bird-curtain")
        XCTAssertTrue(el(curtain, "screen-curtain").waitForExistence(timeout: Live.t(5)), "no curtain")
        XCTAssertFalse(el(curtain, "bird.card.13").exists, "a hand showed behind the curtain")
        XCTAssertFalse(el(curtain, "bird.partner.mark").exists, "a partner mark behind the curtain")
    }
}
