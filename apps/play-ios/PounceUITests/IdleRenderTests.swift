import XCTest

/// Task 24: render on demand. Once nothing moves, the table's SKView is paused and the DEBUG
/// frame counter (`table.frames`) stops; a touch wakes it.
final class IdleRenderTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testTableStopsRenderingWhenIdle() throws {
        let app = Live.demo("table")
        app.launch()
        let frames = el(app, "table.frames")
        XCTAssertTrue(frames.waitForExistence(timeout: 10))

        // Cat blinks (idle flourishes) run 5–9 s apart for a minute after a change, so wait for
        // a 3 s stretch with the counter flat rather than reading at fixed times.
        var last = value(frames)
        var flatSince = Date()
        var stretch: (from: String, to: String)?
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
            let now = value(frames)
            if now != last {
                last = now
                flatSince = Date()
            } else if Date().timeIntervalSince(flatSince) >= 3, let now {
                stretch = (now, now)
                break
            }
        }
        XCTAssertNotNil(stretch, "the frame counter never held still for 3 s (last \(last ?? "-"))")
        let idle = Int(stretch?.to ?? "") ?? 0
        let note = XCTAttachment(string: "frames flat at \(idle) for 3 s")
        note.lifetime = .keepAlways
        add(note)

        // A touch on the deck wakes the view: the counter moves again.
        el(app, "table.deck").tap()
        XCTAssertTrue(until(3) { (Int(value(frames) ?? "") ?? 0) > idle }, "the tap didn't wake the view")
        let woke = XCTAttachment(string: "frames after the tap: \(value(frames) ?? "-") (idle \(idle))")
        woke.lifetime = .keepAlways
        add(woke)
    }
}
