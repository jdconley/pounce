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
        // A fresh simulator has no push answer yet, so the table puts the priming screen up.
        let notNow = el(app, "priming.notNow")
        if notNow.waitForExistence(timeout: 2) {
            dismissPriming(app)
            XCTAssertTrue(notNow.waitForNonExistence(timeout: 3))
        }
        // The tower is folded to a tab: the first tap opens it, a tap on the open tower brings
        // up the scoreboard.
        openTower(app)
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

    /// A tap anywhere else folds the open tower; the paw menu's Scores brings up the scoreboard.
    @MainActor
    func testTowerFoldsAndMenuOpensScoreboard() throws {
        let app = Live.demo("table")
        app.launch()
        let tower = app.descendants(matching: .any)["table.tower"]
        XCTAssertTrue(tower.waitForExistence(timeout: 10))
        let notNow = el(app, "priming.notNow")
        if notNow.waitForExistence(timeout: 2) {
            dismissPriming(app)
            XCTAssertTrue(notNow.waitForNonExistence(timeout: 3))
        }
        openTower(app)
        XCTAssertTrue(value(tower)?.contains("Kiki, level 7") ?? false, value(tower) ?? "-")
        // The rug, right of the open tower: folds it, no scoreboard.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.45)).tap()
        XCTAssertTrue(until(3) { value(tower) == nil }, "the tower didn't fold")
        XCTAssertFalse(app.descendants(matching: .any)["scoreboard"].exists)

        el(app, "table.menu").tap()
        let scores = el(app, "menu.scores")
        XCTAssertTrue(scores.waitForExistence(timeout: 3))
        scores.tap()
        XCTAssertTrue(app.descendants(matching: .any)["scoreboard"].waitForExistence(timeout: 3))
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
