import XCTest

/// The gameplay gate on every UI test (`docs/main-thread.md`): when a test ends, each app it
/// launched through `Live` (`Live.app()`, `Live.demo(...)`) has its watchdog read, and the test
/// fails if, while a table was on screen (from a second after it appeared), the app's own work
/// hung the main thread for over 100 ms, or a frame held more than 8.3 ms (a 120 Hz frame) of the
/// app's own work: its `FrameWork` pieces (redraws, reconciles, touches, textures). On a machine
/// measured several times slower than the reference (a CI virtual machine) those budgets scale
/// and the work is judged at p95, with a cap on the worst frame (`Watchdog.timeFailures`). A hang
/// the app's work didn't fill is reported, not gated. Launch and the way into a table don't count, nor do frames that held, or came within 0.25 s of, a read of the screen:
/// the accessibility runtime a UI test loads into the app runs inside the app's work then (a
/// drag's redraw that takes 5 ms takes 12 to 16 ms in the frame a query lands in).
///
/// It doesn't gate the frame times themselves: a UI test's own reads of the screen stall the app
/// (each one snapshots the accessibility tree on the main thread), and on the simulator they cost
/// frames over 16.7 ms that the app doesn't. `FrameRateTests` gates frame times, on tables that
/// play themselves with nothing reading the screen.
///
/// The test bundle's principal class (`INFOPLIST_KEY_NSPrincipalClass` in `project.yml`), so it
/// sees every test start.
@objc(GameplayGate)
final class GameplayGate: NSObject, XCTestObservation {
    nonisolated(unsafe) private static var current: XCTestCase?
    nonisolated(unsafe) private static var watched: Set<ObjectIdentifier> = []

    override init() {
        super.init()
        XCTestObservationCenter.shared.addTestObserver(self)
    }

    func testCaseWillStart(_ testCase: XCTestCase) {
        Self.current = testCase
        Self.watched = []
    }

    func testCaseDidFinish(_ testCase: XCTestCase) {
        Self.current = nil
    }

    /// Thread Performance Checker settings for the app (the test plan loads it into the app and
    /// fails a test on each report). Its reports also go to the unified log, naming the call
    /// ("antipattern trigger"): `xcrun simctl spawn <device> log show --last 10m --predicate
    /// 'process == "Pounce" AND subsystem == "com.apple.runtime-issues"'`.
    ///
    /// Its main-thread file IO check stays off unless `POUNCE_TPC_IO=1` is in the runner's
    /// environment (`TEST_RUNNER_POUNCE_TPC_IO=1`): iOS itself reads and writes files on the main
    /// thread at every launch (MobileGestalt through ManagedConfiguration, and UIKit), so with it
    /// on every test fails, whatever the app does. The app's own IO is caught by
    /// `scripts/main-thread-lint.swift` instead.
    nonisolated static let checkerEnvironment: [String: String] = {
        var env = ["PERFC_LOG_REPORTS_TO_OSLOG": "1"]
        if ProcessInfo.processInfo.environment["POUNCE_TPC_IO"] == "1" { env["PERFC_ENABLE_IO_ON_MAIN_THREAD"] = "1" }
        return env
    }()

    /// Checks `app`'s gameplay when the running test ends.
    @MainActor static func watch(_ app: XCUIApplication) {
        app.launchEnvironment.merge(checkerEnvironment) { _, new in new }
        guard let test = current, watched.insert(ObjectIdentifier(app)).inserted else { return }
        nonisolated(unsafe) let app = app
        test.addTeardownBlock { @MainActor in test.checkGameplay(app) }
    }
}

@MainActor
extension XCTestCase {
    /// Fails the test on a gameplay hang or a frame over the app's work budget (see `GameplayGate`).
    /// Nothing to check when the app isn't running or never reached a table.
    func checkGameplay(_ app: XCUIApplication) {
        guard app.state == .runningForeground, let dog = watchdog(app) else { return }
        guard dog.link.count + dog.tableFrames.count + dog.hangs > 0 else { return }
        let report = dog.report("gameplay \(name)")
        print(report)
        let note = XCTAttachment(string: report)
        note.name = "gameplay-frames"
        note.lifetime = .keepAlways
        add(note)
        // Hangs count when the app's own work filled them; time budgets fit the machine.
        for failure in dog.timeFailures() { XCTFail("\(failure) during gameplay: \(report)") }
    }
}
