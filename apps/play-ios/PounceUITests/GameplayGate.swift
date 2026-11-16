import XCTest

/// The gameplay gate on every UI test (`docs/main-thread.md`): when a test ends, each app it
/// launched through `Live` (`Live.app()`, `Live.demo(...)`) has its watchdog read, and the test
/// fails if, while a table was on screen (from a second after it appeared), the main thread hung
/// for over 100 ms, or the table dropped frames beyond `GameplayGate.slowShare`. Launch, the way
/// into a table and the test's own accessibility reads don't count (the watchdog sets those apart).
///
/// The test bundle's principal class (`INFOPLIST_KEY_NSPrincipalClass` in `project.yml`), so it
/// sees every test start.
@objc(GameplayGate)
final class GameplayGate: NSObject, XCTestObservation {
    /// At most this share of the table's gameplay frames may be over 16.7 ms, beyond `slowFloor`.
    nonisolated static let slowShare = 0.05
    nonisolated static let slowFloor = 10

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
    /// Fails the test on a gameplay hang or too many slow table frames (see `GameplayGate`).
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
        // On a busy Mac (`POUNCE_UITEST_TIMEOUT_SCALE` over 1) a hang has to be that much longer.
        let hung = dog.hangs > 0 && dog.hangMaxMs > 100 * Live.scale
        XCTAssertFalse(hung, "the main thread hung during gameplay (\(dog.hangs) over 100 ms, worst \(Int(dog.hangMaxMs)) ms): \(report)")
        let allowed = max(GameplayGate.slowFloor, Int(Double(dog.tableFrames.count) * GameplayGate.slowShare))
        XCTAssertLessThanOrEqual(dog.tableFrames.slow, allowed, "the table dropped frames during gameplay (over 16.7 ms): \(report)")
    }
}
