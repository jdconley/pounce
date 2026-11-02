import XCTest

/// All ten phases under the scoreboard, with every seat's cat on its own phase. `-demo table`:
/// Mia (me, seat 0) on phase 3, Leo laid phase 1, Kiki on 7, House Cat on 4.
final class PhasesTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testTowerShowsEveryPhaseAndWhoIsOnIt() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "table"]
        app.launch()
        let tower = app.descendants(matching: .any)["table.tower"]
        XCTAssertTrue(tower.waitForExistence(timeout: 10))
        // A fresh simulator has no push answer yet, so the table puts the priming screen up.
        let notNow = el(app, "priming.notNow")
        if notNow.waitForExistence(timeout: 2) {
            dismissPriming(app)
            XCTAssertTrue(notNow.waitForNonExistence(timeout: 3))
        }
        tower.tap()
        XCTAssertTrue(app.descendants(matching: .any)["phases"].waitForExistence(timeout: 3))
        attach(app, "phases-top")

        var labels: [Int: String] = [:]
        for n in 1...10 {
            let phase = app.descendants(matching: .any)["phase.\(n)"]
            XCTAssertTrue(phase.exists, "phase \(n) missing")
            XCTAssertTrue(phase.label.hasPrefix("Phase \(n): "), phase.label)
            labels[n] = phase.label
        }
        XCTAssertEqual(labels[1], "Phase 1: 2 sets of 3. Leo is here. Leo laid it down. Done.")
        XCTAssertEqual(labels[2], "Phase 2: 1 set of 3 + 1 run of 4. Done.")
        XCTAssertEqual(labels[3], "Phase 3: 1 set of 4 + 1 run of 4. Mia is here. Your phase.")
        XCTAssertEqual(labels[4], "Phase 4: 1 run of 7. House Cat is here.")
        XCTAssertEqual(labels[7], "Phase 7: 2 sets of 4. Kiki is here.")
        XCTAssertEqual(labels[8], "Phase 8: 7 cards of one coat.")
        for n in [5, 6, 9, 10] {
            XCTAssertFalse(labels[n]!.contains(" here."), labels[n]!)
        }

        let last = app.descendants(matching: .any)["phase.10"]
        for _ in 0..<4 where !last.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(last.isHittable)
        attach(app, "phases-bottom")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
