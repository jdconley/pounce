import UIKit
import XCTest

/// Screenshots of "Paste invite", Join's words and the offline invite card for a design review,
/// written as PNGs to `INVITE_SHOT_DIR` (`TEST_RUNNER_INVITE_SHOT_DIR` for xcodebuild) with names
/// starting `INVITE_SHOT_PREFIX`. `INVITE_SHOT_TEXT=xxxl` runs at the largest accessibility text
/// size; `INVITE_SHOT_LANDSCAPE=1` turns an iPad sideways. Skipped without a directory.
@MainActor
final class PasteInviteShotTests: XCTestCase {
    private var dir: URL?
    private var prefix = "invite"

    override func setUpWithError() throws {
        continueAfterFailure = true
        let env = ProcessInfo.processInfo.environment
        guard let path = env["INVITE_SHOT_DIR"], !path.isEmpty else { throw XCTSkip("INVITE_SHOT_DIR not set") }
        dir = URL(fileURLWithPath: path, isDirectory: true)
        prefix = env["INVITE_SHOT_PREFIX"] ?? prefix
        try FileManager.default.createDirectory(at: dir!, withIntermediateDirectories: true)
        if env["INVITE_SHOT_LANDSCAPE"] == "1" { XCUIDevice.shared.orientation = .landscapeLeft }
    }

    override func tearDown() {
        UIPasteboard.general.items = []
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    private func save(_ name: String, settle: TimeInterval = 1.2) {
        guard let dir else { return }
        Thread.sleep(forTimeInterval: settle)
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: dir.appendingPathComponent("\(prefix)-\(name).png"))
    }

    private func launch(base: String = Live.baseURL, _ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        var args = Live.arguments() + ["-uitest-reset", "-paste-invite", "-no-tips"] + extra
        if ProcessInfo.processInfo.environment["INVITE_SHOT_TEXT"] == "xxxl" {
            args += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launchArguments = args
        app.launchEnvironment["POUNCE_API_BASE_URL"] = base
        app.launch()
        return app
    }

    func testHomeOffersToPaste() {
        UIPasteboard.general.string = "https://play.conleychaos.com/j/BCDFG"
        let app = launch()
        onboard(app)
        XCTAssertTrue(el(app, "card-pasteInvite").waitForExistence(timeout: Live.t(10)))
        save("home-paste")
    }

    func testJoinPasteAndWrongCode() {
        let app = launch()
        onboard(app)
        el(app, "home.join").tap()
        XCTAssertTrue(el(app, "screen-join").waitForExistence(timeout: Live.t(10)))
        save("join")
        for c in "BCDFG" { el(app, "join.key.\(c)").tap() }
        XCTAssertTrue(el(app, "join.wrong").waitForExistence(timeout: Live.t(15)))
        UIPasteboard.general.string = "https://play.conleychaos.com/j/BCDFH"
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(el(app, "join.paste").waitForExistence(timeout: Live.t(10)))
        save("join-wrong-paste")
    }

    func testOfflineInvite() {
        let app = launch(base: "http://127.0.0.1:9", ["-open-link", "pounce-dev://p/\(String(repeating: "A", count: 22))"])
        let confirm = el(app, "pickcat.confirm")
        XCTAssertTrue(confirm.waitForExistence(timeout: Live.t(15)))
        el(app, "pickcat.dice").tap()
        _ = until(3) { app.keyboards.count == 0 }
        confirm.tap()
        XCTAssertTrue(el(app, "card-offlineInvite").waitForExistence(timeout: Live.t(20)))
        save("pounce-offline")
    }
}
