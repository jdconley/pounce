import XCTest

/// Task H: the pass-and-play hold can't be cheated, Join can always delete while a code is
/// checked and shows the offline card when the server can't be reached, and leaving a table
/// frees its scene (`[scene] deinit` in the app's output).
final class HardeningTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    private func waitGone(_ e: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: e)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    /// A short press and a press that slides off the paw both leave the curtain up; only a
    /// full hold on the paw lifts it. The hold's timing is what's tested, so this runs at
    /// normal speed whatever the suite's speed.
    @MainActor
    func testCurtainNeedsAFullUnbrokenHold() throws {
        let app = Live.demo("curtain", speed: 1)
        app.launch()
        let curtain = element(app, "screen-curtain")
        let hold = element(app, "curtain.hold")
        XCTAssertTrue(hold.waitForExistence(timeout: 10))

        hold.press(forDuration: 0.2)
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(curtain.exists, "a short press revealed the hand")

        // Down on the paw, then slide far off it and stay down past the hold time.
        let start = hold.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let away = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
        start.press(forDuration: 0.1, thenDragTo: away, withVelocity: .fast, thenHoldForDuration: 1.0)
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(curtain.exists, "sliding off the paw still revealed the hand")

        hold.press(forDuration: 1.2)
        XCTAssertTrue(waitGone(curtain, timeout: 5), "a full hold didn't lift the curtain")
    }

    /// A code being checked against a server that never answers: delete still works (and
    /// cancels the check).
    @MainActor
    func testJoinDeleteWorksWhileChecking() throws {
        let app = XCUIApplication()
        app.launchArguments = Live.arguments() + ["-uitest-reset"]
        app.launchEnvironment["POUNCE_API_BASE_URL"] = "http://10.255.255.1:8787"  // blackholed
        app.launch()
        onboard(app)
        let join = element(app, "home.join")
        XCTAssertTrue(join.waitForExistence(timeout: 10))
        join.tap()
        for c in "BCDFG" { element(app, "join.key.\(c)").tap() }
        let delete = element(app, "join.key.delete")
        XCTAssertTrue(delete.isEnabled, "delete is disabled while the code is checked")
        XCTAssertFalse(element(app, "join.key.H").isEnabled)
        delete.tap()
        XCTAssertTrue(element(app, "join.key.H").waitForExistence(timeout: 2))
        XCTAssertTrue(element(app, "join.key.H").isEnabled, "the check wasn't cancelled")
        XCTAssertEqual(element(app, "join.tile.4").label, "Empty")
    }

    /// A code checked against a server that refuses connections: the offline card, not a
    /// spinner forever.
    @MainActor
    func testJoinShowsOfflineWhenTheServerIsUnreachable() throws {
        let app = XCUIApplication()
        app.launchArguments = Live.arguments() + ["-uitest-reset"]
        app.launchEnvironment["POUNCE_API_BASE_URL"] = "http://127.0.0.1:9"  // refused
        app.launch()
        onboard(app)
        let join = element(app, "home.join")
        XCTAssertTrue(join.waitForExistence(timeout: 10))
        join.tap()
        for c in "BCDFG" { element(app, "join.key.\(c)").tap() }
        XCTAssertTrue(element(app, "state.retry").waitForExistence(timeout: 30))
        XCTAssertTrue(element(app, "state.home").exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "join-offline"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Opens a table, goes home through the paw menu and waits: the scene must be freed
    /// (`[scene] deinit` lands in this test's app output in the result bundle). Home needs an
    /// owner on the device, so a fresh simulator onboards first.
    @MainActor
    func testLeavingTheTableFreesTheScene() throws {
        ensureOwner()
        let app = Live.demo("table")
        app.launch()
        let menu = element(app, "table.menu")
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
        let home = element(app, "menu.home")
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        home.tap()
        XCTAssertTrue(element(app, "screen-home").waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 2)
    }
}
