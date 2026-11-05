import XCTest

/// Screenshots of a pounce as it lands (spec §12.5): the communication notification with Mia's cat
/// as the avatar, drawn by the same code as `PounceNotify` (the app's Debug `-demo-communication`
/// posts it, since `simctl push` skips service extensions), as a banner and expanded with its
/// Play, In a bit and Not now buttons. Skipped unless the runner's environment names a folder:
///
///     TEST_RUNNER_POUNCE_SHOTS_DIR=/some/dir xcodebuild test ... -only-testing:PounceUITests/PushShotTests
///
/// `POUNCE_SHOTS_ORIENTATIONS=landscape` turns the device first. The shots land as
/// `push-banner-<orientation>.png` and `push-<orientation>.png`.
@MainActor
final class PushShotTests: XCTestCase {
    func testPounceNotification() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["POUNCE_SHOTS_DIR"], !dir.isEmpty else { throw XCTSkip("no POUNCE_SHOTS_DIR") }
        let orientation = env["POUNCE_SHOTS_ORIENTATIONS"] == "landscape" ? "landscape" : "portrait"
        XCUIDevice.shared.orientation = orientation == "landscape" ? .landscapeLeft : .portrait
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let app = XCUIApplication()
        app.launchArguments = Live.arguments(speed: 1)
            + ["-uitest-reset", "-seed-people", "-demo-streaks", "-request-push", "-demo-communication"]
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
        XCTAssertTrue(el(app, "home.streak").waitForExistence(timeout: 10))
        // The pounce is scheduled by now; it lands over the Home Screen.
        Thread.sleep(forTimeInterval: 1)
        XCUIDevice.shared.press(.home)

        let banner = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'wants to play'")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 20), "no banner")
        Thread.sleep(forTimeInterval: 1)
        try XCUIScreen.main.screenshot().pngRepresentation
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent("push-banner-\(orientation).png"))
        // Expanded: the long-press shows the buttons. On iPad the press dismisses the banner
        // instead, so the banner shot is the one to use there.
        banner.press(forDuration: 1.2)
        guard springboard.buttons["In a bit"].waitForExistence(timeout: 10) else {
            XCUIDevice.shared.orientation = .portrait
            throw XCTSkip("the banner didn't expand (iPad): use push-banner-\(orientation).png")
        }
        Thread.sleep(forTimeInterval: 1)
        try XCUIScreen.main.screenshot().pngRepresentation
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent("push-\(orientation).png"))
        XCUIDevice.shared.orientation = .portrait
    }
}
