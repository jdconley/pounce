import XCTest

/// Task 18: the scoreboard behind the tower, and `-demo celebrate` ending on the game-over
/// overlay with the table paused.
final class CelebrationTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testTowerOpensScoreboard() throws {
        let app = Live.demo("table")
        app.launch()
        let tower = app.descendants(matching: .any)["table.tower"]
        XCTAssertTrue(tower.waitForExistence(timeout: 10))
        // By coordinate: the tower's element starts just past the screen's left edge, XCUITest
        // finds no hit point for it ({-1, -1}), and `tower.tap()` lands nowhere.
        tap(app, tower.frame)
        let board = app.descendants(matching: .any)["scoreboard"]
        XCTAssertTrue(board.waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["scoreboard.0"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["scoreboard.3"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "scoreboard"
        shot.lifetime = .keepAlways
        add(shot)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: board)
        wait(for: [gone], timeout: 3)
    }

    @MainActor
    func testCelebrateEndsOnGameOverWithTheTablePaused() throws {
        let app = Live.demo("celebrate")
        app.launch()
        let home = app.descendants(matching: .any)["gameover.home"]
        XCTAssertTrue(home.waitForExistence(timeout: 45))
        XCTAssertTrue(app.descendants(matching: .any)["gameover.new"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["gameover.winner"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "gameover"
        shot.lifetime = .keepAlways
        add(shot)
        // The sunburst stops and the view pauses: the frame counter goes flat.
        let frames = app.descendants(matching: .any)["table.frames"]
        XCTAssertTrue(frames.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1.5)
        let a = frames.value as? String
        Thread.sleep(forTimeInterval: 3)
        let b = frames.value as? String
        XCTAssertNotNil(a)
        XCTAssertEqual(a, b)
    }
}
