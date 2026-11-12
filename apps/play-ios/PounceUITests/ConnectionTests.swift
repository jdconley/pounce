import XCTest

/// The bad connection indicator, on the demo tables (a fake server with links): this phone's
/// own connection in a pill under the top bar, the other players' on their seats, and a move
/// the server hasn't answered kept in flight.
class ConnectionTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// `-demo weak`: round trips turn slow a second in.
    @MainActor
    func testAWeakLinkShowsThePill() throws {
        let app = Live.demo("weak")
        app.launch()
        let pill = el(app, "table.connection")
        XCTAssertTrue(pill.waitForExistence(timeout: Live.t(10)), "no connection pill")
        XCTAssertEqual(value(pill), "weak")
        XCTAssertEqual(label(pill), "Weak signal")
        screenshot(app, "connection-weak")
    }

    /// `-demo reconnecting`: the socket drops a second in; the pill says so a second later.
    @MainActor
    func testADroppedSocketShowsReconnecting() throws {
        let app = Live.demo("reconnecting")
        app.launch()
        let pill = el(app, "table.connection")
        XCTAssertTrue(pill.waitForExistence(timeout: Live.t(10)), "no connection pill")
        XCTAssertTrue(until(3) { self.value(pill) == "reconnecting" }, value(pill) ?? "-")
        XCTAssertEqual(label(pill), "Reconnecting")
        screenshot(app, "connection-reconnecting")
    }

    /// `-demo seatLink`: Kiki's turn on a weak phone, Leo's phone reconnecting.
    @MainActor
    func testOtherPlayersLinksShowOnTheirSeats() throws {
        let app = Live.demo("seatLink")
        app.launch()
        let kiki = el(app, "table.opponent.2")
        XCTAssertTrue(kiki.waitForExistence(timeout: Live.t(10)), "no seat 2")
        XCTAssertTrue(until(3) { self.label(kiki)?.hasSuffix("Weak signal") == true }, label(kiki) ?? "-")
        XCTAssertTrue(label(el(app, "table.opponent.1"))?.hasSuffix("Offline") == true, label(el(app, "table.opponent.1")) ?? "-")
        XCTAssertFalse(label(el(app, "table.opponent.3"))?.contains("signal") == true)
        XCTAssertFalse(el(app, "table.connection").exists, "this phone's own link is fine")
        screenshot(app, "connection-seat-link")
    }

    /// `-demo pending`: a discard the server never answers stays in flight (and under its
    /// hourglass), with no rollback.
    @MainActor
    func testAnUnansweredMoveStaysPending() throws {
        let app = Live.demo("pending")
        app.launch()
        XCTAssertTrue(el(app, "table.debug").waitForExistence(timeout: Live.t(10)), "no table probe")
        XCTAssertTrue(until(5) { self.debug(app)?.inFlight == true }, value(el(app, "table.debug")) ?? "-")
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(debug(app)?.inFlight, true, "the move was given up")
        screenshot(app, "connection-pending")
    }
}
