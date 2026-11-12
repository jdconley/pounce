import XCTest

/// How to play is per game: each game in the catalog has its own page with its video on top
/// (the poster and play button, then the player) and its own rules under it. Needs no server:
/// `-show-rules` opens it over Home.
@MainActor
final class HowToPlayTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testEachGameHasItsVideoAndItsRules() {
        let app = XCUIApplication()
        app.launchArguments = Live.arguments() + ["-uitest-reset", "-seed-people", "-show-rules"]
        app.launch()
        XCTAssertTrue(el(app, "sheet-rules").waitForExistence(timeout: Live.t(10)), "no How to play")
        XCTAssertTrue(el(app, "rules.game.cat-tower").isSelected, "How to play should open on Cat Tower")
        checkVideo(app, game: "Cat Tower")
        XCTAssertTrue(el(app, "rules.replay").exists, "Cat Tower's page brings the tips back")
        screenshot(app, "howto-cat-tower")

        el(app, "rules.game.tiles").tap()
        XCTAssertTrue(until(3) { self.el(app, "rules.game.tiles").isSelected }, "the tile game was not picked")
        checkVideo(app, game: "Tuna Tiles")
        XCTAssertFalse(el(app, "rules.replay").exists, "the tile game has no first-game tips to bring back")
        screenshot(app, "howto-tiles")
    }

    /// The poster names the video for VoiceOver; a tap swaps it for the player.
    private func checkVideo(_ app: XCUIApplication, game: String) {
        let poster = el(app, "rules.video")
        XCTAssertTrue(poster.waitForExistence(timeout: Live.t(5)), "no video for \(game)")
        XCTAssertTrue(poster.label.hasPrefix("How to play \(game), a video with captions"), poster.label)
        poster.tap()
        XCTAssertTrue(el(app, "rules.video.player").waitForExistence(timeout: Live.t(5)), "no player for \(game)")
    }
}
