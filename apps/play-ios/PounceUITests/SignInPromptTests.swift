import XCTest

/// Home's worded sign-in card (launch review): once a pair formed, a signed-out adult is told that
/// a new phone loses the streak, with Sign in with Apple and "Not now". `-signin-prompt` lets it
/// show under `-uitest-reset`; `-demo-streaks` brings the pairs. No server needed.
@MainActor
final class SignInPromptTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = Live.arguments() + ["-uitest-reset", "-seed-people", "-demo-streaks"] + extra
        app.launchEnvironment["POUNCE_API_BASE_URL"] = Live.baseURL
        app.launch()
        return app
    }

    func testCardShowsOnceAndNotNowDismisses() {
        let app = launch(["-signin-prompt"])
        XCTAssertTrue(el(app, "home.signinPrompt").waitForExistence(timeout: Live.t(10)), "no sign-in card with a pair")
        XCTAssertTrue(el(app, "home.signinPrompt.apple").exists, "no Sign in with Apple on the card")
        el(app, "home.signinPrompt.notNow").tap()
        XCTAssertTrue(until(3) { !self.el(app, "home.signinPrompt").exists }, "Not now didn't close the card")
        // The streak badge's cloud says what it is.
        let cloud = el(app, "home.streak.cloud")
        if cloud.waitForExistence(timeout: Live.t(3)) {
            XCTAssertTrue((label(cloud) ?? "").contains("Sign in"), "the cloud has no words")
        }
    }

    func testNoCardForAKitten() {
        let app = launch(["-signin-prompt", "-age-band", "kitten"])
        XCTAssertTrue(el(app, "screen-home").waitForExistence(timeout: Live.t(10)), "no Home")
        Thread.sleep(forTimeInterval: Live.pace(1.5))
        XCTAssertFalse(el(app, "home.signinPrompt").exists, "a kitten was offered sign-in")
    }

    func testNoCardSignedIn() {
        let app = launch(["-signin-prompt", "-stub-accounts", "signed-in"])
        XCTAssertTrue(el(app, "screen-home").waitForExistence(timeout: Live.t(10)), "no Home")
        Thread.sleep(forTimeInterval: Live.pace(1.5))
        XCTAssertFalse(el(app, "home.signinPrompt").exists, "a signed-in person was offered sign-in")
    }
}
