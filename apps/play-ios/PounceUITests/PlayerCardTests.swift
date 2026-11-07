import XCTest

/// Tap a cat in the table's top bar: that player's card (PlayerCardView.swift). The streak with
/// them lives on the card, never on the table. And a swipe in from the left edge goes Home.
/// `-demo table` with `-demo-streaks`: Mia (me) at a table with Leo (whose streak was left, so
/// not connected), Kiki (connected, a win-back at 9) and a House Cat. No server.
@MainActor
final class PlayerCardTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func table(_ extra: [String] = []) -> XCUIApplication {
        let app = Live.demo("table")
        app.launchArguments += ["-uitest-reset", "-seed-people", "-demo-streaks"] + extra
        app.launch()
        XCTAssertTrue(el(app, "table.menu").waitForExistence(timeout: Live.t(10)), "no table")
        if el(app, "priming.notNow").waitForExistence(timeout: Live.t(3)) { dismissPriming(app) }
        _ = until(5) { !self.el(app, "priming.notNow").exists }
        return app
    }

    private func openCard(_ app: XCUIApplication, seat: Int) -> XCUIElement {
        let cat = el(app, "table.opponent.\(seat)")
        XCTAssertTrue(cat.waitForExistence(timeout: Live.t(10)), "no cat for seat \(seat)")
        tap(app, cat.frame)
        let card = el(app, "player")
        XCTAssertTrue(card.waitForExistence(timeout: Live.t(5)), "no player card for seat \(seat)")
        return card
    }

    func testConnectedPlayerShowsTheStreakOnTheCardNotTheTable() {
        let app = table()
        // The streak badge is gone from the table.
        Thread.sleep(forTimeInterval: Live.pace(1))
        XCTAssertFalse(el(app, "table.streak").exists, "a streak badge on the table")

        let card = openCard(app, seat: 2)
        XCTAssertEqual(label(el(app, "player.name")), "Kiki")
        XCTAssertEqual(label(el(app, "player.kind")), "Human player · asleep")
        XCTAssertEqual(value(el(app, "player.phase")), "7")
        XCTAssertEqual(value(el(app, "player.cards")), "10")
        let streak = el(app, "player.streak")
        XCTAssertTrue(streak.waitForExistence(timeout: Live.t(5)), "no streak on Kiki's card")
        XCTAssertTrue(value(streak)?.hasPrefix("9|") ?? false, "streak \(String(describing: value(streak)))")
        screenshot(app, "player-card-connected")

        // A tap on the card itself keeps it; a tap outside puts it away.
        tap(app, el(app, "player.cards").frame)
        XCTAssertTrue(card.exists, "a tap on the card closed it")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        XCTAssertTrue(until(5) { !card.exists }, "a tap outside didn't close the card")
    }

    func testNotConnectedAndBot() {
        let app = table()
        let card = openCard(app, seat: 1)
        XCTAssertEqual(label(el(app, "player.name")), "Leo")
        XCTAssertTrue(el(app, "player.notConnected").exists, "Leo's card doesn't say you're not connected")
        XCTAssertFalse(el(app, "player.streak").exists)
        screenshot(app, "player-card-not-connected")
        el(app, "player.close").tap()
        XCTAssertTrue(until(5) { !card.exists }, "the close button didn't close the card")

        _ = openCard(app, seat: 3)
        XCTAssertEqual(label(el(app, "player.kind")), "Computer player")
        XCTAssertFalse(el(app, "player.streak").exists, "a bot has a streak")
        XCTAssertFalse(el(app, "player.notConnected").exists, "a bot offers a connection")
        screenshot(app, "player-card-bot")
    }

    /// A swipe in from the left edge goes Home; a card dragged right from the hand doesn't.
    func testEdgeSwipeGoesHome() {
        let app = table()
        let first = el(app, "table.hand.0")
        XCTAssertTrue(first.waitForExistence(timeout: Live.t(10)), "no hand")
        let from = first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        from.press(forDuration: 0.1, thenDragTo: from.withOffset(CGVector(dx: 160, dy: -10)))
        Thread.sleep(forTimeInterval: Live.pace(1))
        XCTAssertFalse(el(app, "screen-home").exists, "a card drag went Home")
        XCTAssertTrue(el(app, "table.menu").exists)

        let mid = app.frame.height * 0.45
        let edge = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 2, dy: mid))
        edge.press(forDuration: 0.05, thenDragTo: edge.withOffset(CGVector(dx: 220, dy: 0)))
        XCTAssertTrue(el(app, "screen-home").waitForExistence(timeout: Live.t(5)), "the edge swipe didn't go Home")
    }
}
