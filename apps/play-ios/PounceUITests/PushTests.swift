import XCTest

/// Task 24 (needs the dev server and the host broker: run with scripts/ui-tests.sh): a real table with a remote human, push
/// allowed through the priming screen, the app sent Home and then to the background; a "your
/// turn" push for that room (`xcrun simctl push`, shaped like scripts/push-sample.apns) shows a
/// banner, and tapping it opens that table.
final class PushTests: XCTestCase {
    private var remote: HostProcess?

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        remote?.stop()
        remote = nil
    }

    @MainActor
    func testPushBannerOpensTheTable() throws {
        guard let udid = ProcessInfo.processInfo.environment["SIMULATOR_UDID"] else {
            throw XCTSkip("runs on a simulator")
        }
        let app = Live.app()
        app.launch()
        onboard(app)
        newGame(app)
        let code = lobbyCode(app)
        remote = try HostProcess("e2e", ["join", code, "--name", "Remote", "--cat", "6", "--base", Live.baseURL])
        XCTAssertTrue(until(30) { self.el(app, "lobby.seat.1").label.contains("on another phone") }, "the remote never sat")
        el(app, "lobby.start").tap()

        // The first table with a human on another phone primes push; allow it (system alert too).
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = el(app, "priming.allow")
        if allow.waitForExistence(timeout: 10) {
            allow.tap()
            let system = springboard.alerts.buttons["Allow"]
            if system.waitForExistence(timeout: 10) { system.tap() }
        }
        XCTAssertTrue(el(app, "table.turn").waitForExistence(timeout: 15), "no table")

        // Home, then the background.
        el(app, "table.menu").tap()
        let home = el(app, "menu.home")
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        home.tap()
        XCTAssertTrue(el(app, "screen-home").waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)

        let payload = NSTemporaryDirectory() + "push-\(code).apns"
        let json = """
            {"Simulator Target Bundle":"com.conleychaos.play","aps":{"alert":{"title":"Remote","body":"Your turn"},\
            "sound":"default","thread-id":"\(code)"},"code":"\(code)"}
            """
        try json.write(toFile: payload, atomically: true, encoding: .utf8)
        let push = try HostProcess("push", [udid, "com.conleychaos.play", payload])
        XCTAssertEqual(push.wait(), 0, "simctl push failed: \(push.output())")

        let banner = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Your turn'")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 15), "no banner")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "push-banner"
        shot.lifetime = .keepAlways
        add(shot)
        banner.tap()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(el(app, "screen-table").waitForExistence(timeout: 20), "the banner didn't open the table")
        XCTAssertTrue(el(app, "table.turn").waitForExistence(timeout: 10))
        screenshot(app, "push-opened-table")
    }
}
