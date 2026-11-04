import XCTest

/// Shared helpers for the UI tests that play against the local dev server (Task 24).
///
/// The server URL comes from the test runner's `POUNCE_API_BASE_URL` (pass
/// `TEST_RUNNER_POUNCE_API_BASE_URL=…` to xcodebuild), default `http://localhost:8787`.
///
/// Every app a test launches runs at `Live.speed` (`-anim-speed`, which also swaps sound and
/// haptics for silent stand-ins), and fixed waits for an animation and poll intervals shrink to
/// match (`Live.pace`). Timeouts (`Live.t`) stay as they are: they are upper bounds, and a
/// condition that holds early ends its wait early.
@MainActor
enum Live {
    /// The app's speed under test: `POUNCE_SPEED` in the runner's environment (the scripts'
    /// `SPEED`, as `TEST_RUNNER_POUNCE_SPEED`), default 10; 1 is normal speed.
    nonisolated static let speed: Double = {
        let raw = ProcessInfo.processInfo.environment["POUNCE_SPEED"].flatMap(Double.init) ?? 10
        return raw > 0 ? raw : 1
    }()

    /// A fixed wait of `seconds` at normal speed, at the test speed (never under `floor`, nor
    /// longer than at normal speed).
    nonisolated static func pace(_ seconds: TimeInterval, floor: TimeInterval = 0.1) -> TimeInterval {
        max(seconds / speed, min(floor, seconds))
    }

    /// A poll interval of `seconds` at normal speed, at the test speed. Floored at 0.25 s: every
    /// poll snapshots the app's accessibility tree on its main thread, and polling much faster
    /// starves the table's SpriteKit frames.
    nonisolated static func poll(_ seconds: TimeInterval) -> TimeInterval { pace(seconds, floor: 0.25) }

    /// The launch arguments every test app gets (see `Live.speed`).
    nonisolated static func arguments(speed: Double = speed) -> [String] {
        ["-anim-speed", String(speed)]
    }

    /// An app on a `-demo` screen (no server) at `speed`.
    static func demo(_ name: String, speed: Double = speed) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments(speed: speed) + ["-demo", name]
        return app
    }

    /// Multiplies every live timeout (`POUNCE_UITEST_TIMEOUT_SCALE` in the runner's environment,
    /// `TEST_RUNNER_POUNCE_UITEST_TIMEOUT_SCALE=3` for xcodebuild; default 1) so a merely slow
    /// machine still passes.
    nonisolated static let scale: Double = {
        let raw = ProcessInfo.processInfo.environment["POUNCE_UITEST_TIMEOUT_SCALE"].flatMap(Double.init) ?? 1
        return raw > 0 ? raw : 1
    }()

    /// A live timeout, scaled.
    nonisolated static func t(_ seconds: TimeInterval) -> TimeInterval { seconds * scale }

    static var baseURL: String {
        ProcessInfo.processInfo.environment["POUNCE_API_BASE_URL"] ?? "http://localhost:8787"
    }

    /// A fresh app (scratch data, in-memory credential) pointed at the dev server.
    static func app() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments() + ["-uitest-reset"]
        app.launchEnvironment["POUNCE_API_BASE_URL"] = baseURL
        return app
    }
}

/// The DEBUG `table.debug` value:
/// `step|inFlight|hand size|laid|turn|animating|round|status|store seq|stage seq|pass`.
struct TableDebug: Equatable {
    var step = ""
    var inFlight = false
    var handCount = -1
    var laid = false
    var turn = -1
    var busy = false
    var round = 0
    var status = ""
    /// The store's last seq, and the one the SwiftUI shell last synced the table at.
    var storeSeq = -1
    var stageSeq = -1
    /// The shell's pass-and-play state when it last synced: `none`, `curtain<n>`, `revealed<n>`.
    var pass = ""

    init?(_ value: String?) {
        guard let parts = value?.split(separator: "|").map(String.init), parts.count >= 8 else { return nil }
        step = parts[0]
        inFlight = parts[1] == "1"
        handCount = Int(parts[2]) ?? -1
        laid = parts[3] == "1"
        turn = Int(parts[4]) ?? -1
        busy = parts[5] == "1"
        round = Int(parts[6]) ?? 0
        status = parts[7]
        if parts.count >= 11 {
            storeSeq = Int(parts[8]) ?? -1
            stageSeq = Int(parts[9]) ?? -1
            pass = parts[10]
        }
    }

    /// The shell has synced the store's latest room (true when the probe is missing).
    var shellCaughtUp: Bool { storeSeq < 0 || stageSeq == storeSeq }

    /// Nothing in flight or animating: the table takes a move.
    var settled: Bool { !inFlight && !busy }
}

@MainActor
extension XCTestCase {
    func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    /// Polls `condition` every 0.5 s (at the test speed, `Live.poll`) until it holds or `timeout`
    /// (scaled by `Live.scale`) passes. (Every query snapshots the app's accessibility tree on
    /// its main thread; polling faster starves the table's SpriteKit frames, and its animations
    /// crawl.)
    @discardableResult
    func until(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(Live.t(timeout))
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: Live.poll(0.5))
        }
        return condition()
    }

    /// The element's value, or nil if it isn't there (a snapshot: no failure if it just left).
    func value(_ e: XCUIElement) -> String? {
        (try? e.snapshot())?.value as? String
    }

    /// The element's label, or nil if it isn't there.
    func label(_ e: XCUIElement) -> String? {
        (try? e.snapshot())?.label
    }

    func debug(_ app: XCUIApplication) -> TableDebug? {
        TableDebug(value(el(app, "table.debug")))
    }

    func screenshot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Onboarding with a dice-rolled name and the first cat, then Home.
    func onboard(_ app: XCUIApplication) {
        let confirm = el(app, "pickcat.confirm")
        XCTAssertTrue(confirm.waitForExistence(timeout: Live.t(15)), "no pick-a-cat screen")
        el(app, "pickcat.dice").tap()
        _ = until(3) { app.keyboards.count == 0 }  // the keyboard drops away from the check
        confirm.tap()
        XCTAssertTrue(el(app, "home.newGame").waitForExistence(timeout: Live.t(10)), "no Home")
    }

    /// Gives this device an owner if it has none (a fresh simulator opens on pick-a-cat): one
    /// launch on its own data, onboarding if asked, then the app is closed again. For tests that
    /// run on the device's data, not `-uitest-reset`, and need Home.
    func ensureOwner() {
        let app = XCUIApplication()
        app.launchArguments = Live.arguments()
        app.launch()
        if el(app, "pickcat.confirm").waitForExistence(timeout: Live.t(5)) { onboard(app) }
        app.terminate()
    }

    /// New game from Home; returns once this phone sits at seat 0 of the new lobby.
    func newGame(_ app: XCUIApplication) {
        el(app, "home.newGame").tap()
        let seat0 = el(app, "lobby.seat.0")
        XCTAssertTrue(seat0.waitForExistence(timeout: Live.t(20)), "no lobby")
        XCTAssertTrue(until(15) { seat0.label.contains("on this phone") }, "seat 0 not claimed: \(seat0.label)")
    }

    /// The room code from the lobby ("Room code B C D F G").
    func lobbyCode(_ app: XCUIApplication) -> String {
        let label = el(app, "lobby.code").label
        let letters = label.replacingOccurrences(of: "Room code", with: "").filter { !$0.isWhitespace }
        return String(letters)
    }

    /// Opens the seat bubble on `seat` and taps `item` (bot, here, invite, remove).
    func seatMenu(_ app: XCUIApplication, seat: Int, _ item: String) {
        el(app, "lobby.seat.\(seat)").tap()
        let button = el(app, "seatmenu.\(item)")
        XCTAssertTrue(button.waitForExistence(timeout: Live.t(5)), "no seat menu item \(item)")
        Thread.sleep(forTimeInterval: Live.pace(1))  // the bubble springs open
        button.tap()
        Thread.sleep(forTimeInterval: Live.pace(1))
    }

    /// In the person picker (after `seatmenu.here`): a new person with a dice-rolled name and the
    /// suggested cat. Taps again while the sheet is still sliding in.
    func addLocalPerson(_ app: XCUIApplication) {
        let addTile = el(app, "picker.add")
        let confirm = el(app, "pickcat.confirm")
        XCTAssertTrue(addTile.waitForExistence(timeout: Live.t(10)), "no person picker")
        XCTAssertTrue(until(15) {
            if confirm.exists { return true }
            if addTile.exists { addTile.tap() }
            return confirm.waitForExistence(timeout: Live.t(2))
        }, "the new-person editor never opened")
        Thread.sleep(forTimeInterval: Live.pace(1))
        el(app, "pickcat.dice").tap()
        _ = until(3) { app.keyboards.count == 0 }  // the keyboard drops away from the check
        confirm.tap()
        _ = until(10) { !confirm.exists }
    }

    /// Closes the system share sheet the lobby's invite put up (its close button, else a tap on
    /// the dimmed area above it).
    func dismissShareSheet(_ app: XCUIApplication) {
        let close = app.buttons["Close"]
        if close.waitForExistence(timeout: Live.t(6)) {
            close.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        }
        _ = until(5) { !app.buttons["Close"].exists }
        Thread.sleep(forTimeInterval: Live.pace(0.5))
    }

    /// Taps the center of `frame` (screen points) without another element query.
    func tap(_ app: XCUIApplication, _ frame: CGRect) {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
    }

    /// Holds the curtain's paw (past its hold time, at the test speed) if the curtain is up in
    /// `snap`; returns the name on it. Presses by coordinate, so a curtain that lifts on its own
    /// (round over) doesn't fail the test.
    @discardableResult
    func holdCurtain(_ app: XCUIApplication, _ snap: UISnap) -> String? {
        guard let paw = snap.frame("curtain.hold") else { return nil }
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: paw.midX, dy: paw.midY))
            .press(forDuration: Live.pace(1.3, floor: 0.3))
        return snap.label("curtain.name") ?? "?"
    }

    /// Dismisses the push priming screen if the table put it up.
    func dismissPriming(_ app: XCUIApplication, _ snap: UISnap? = nil) {
        if let snap {
            if let f = snap.frame("priming.notNow") { tap(app, f) }
            return
        }
        let notNow = el(app, "priming.notNow")
        if notNow.exists { notNow.tap() }
    }

    /// Polls one app snapshot every `every` seconds (at the test speed, `Live.poll`) until
    /// `condition` holds.
    func untilSnap(_ app: XCUIApplication, _ timeout: TimeInterval, every: TimeInterval = 2,
                   _ condition: (UISnap) -> Bool) -> UISnap? {
        let deadline = Date().addingTimeInterval(Live.t(timeout))
        while Date() < deadline {
            if let snap = UISnap(app), condition(snap) { return snap }
            Thread.sleep(forTimeInterval: Live.poll(every))
        }
        return nil
    }

    /// One whole turn by taps for whichever seat of this phone is up and showing: draw from the
    /// deck, then pick the first non-Cucumber hand card and tap the discard (a hand of only
    /// Cucumbers aims the first glowing cat). Returns false if `snap` shows the table isn't
    /// ready. Works from whole-app snapshots polled every 2 s (`Live.poll`) and taps by coordinate: every
    /// element query snapshots the app's accessibility tree on its main thread, and querying
    /// element by element, flat out, starved the app (its table animations crawled, and SwiftUI
    /// updates waited minutes). `observe` sees each polled snapshot.
    @discardableResult
    func playTurnByTaps(_ app: XCUIApplication, _ snap: UISnap, observe: (UISnap) -> Void = { _ in }) -> Bool {
        guard snap.value("table.turn") == "mine", let d = snap.debug, d.settled, d.step == "draw",
              d.status == "playing", let deck = snap.frame("table.deck") else { return false }
        // The hand must be face up: on a pass-and-play phone the scene can already be on this
        // seat's turn a moment before the curtain comes down over it (a face-down card is "Card").
        guard let first = snap.label("table.hand.0"), first != "Card" else { return false }
        tap(app, deck)
        guard let drawn = untilSnap(app, 120, { s in
            observe(s)
            return s.debug.map { $0.step == "play" && $0.settled } ?? false
        }) else {
            XCTFail("the draw never landed: \(String(describing: UISnap(app)?.debug))")
            return false
        }
        let count = drawn.debug?.handCount ?? 0
        let pick = (0..<max(count, 1)).map { "table.hand.\($0)" }.first {
            if let text = drawn.label($0) { return !text.hasPrefix("Cucumber") }
            return false
        }
        if let pick, let card = drawn.frame(pick), let pile = drawn.frame("table.discard") {
            tap(app, card)
            Thread.sleep(forTimeInterval: Live.pace(0.5))
            tap(app, pile)
        } else if let card = drawn.frame("table.hand.0") {
            tap(app, card)
            Thread.sleep(forTimeInterval: Live.pace(1))
            if let cat = UISnap(app)?.items.first(where: { $0.key.hasPrefix("table.opponent.") && $0.value.value == "glowing" }) {
                tap(app, cat.value.frame)
            }
        }
        let done = untilSnap(app, 120) { s in
            observe(s)
            guard let d = s.debug else { return true }  // the curtain came down over the table
            return d.settled && (d.step == "draw" || d.status != "playing")
        } != nil
        XCTAssertTrue(done, "the discard never landed: \(String(describing: UISnap(app)?.debug))")
        return done
    }
}

/// Everything with an accessibility identifier in one snapshot of the app (one accessibility
/// request instead of one per element).
struct UISnap {
    struct Item {
        var label: String
        var value: String?
        var frame: CGRect
    }

    let items: [String: Item]

    @MainActor init?(_ app: XCUIApplication) {
        guard let root = try? app.snapshot() else { return nil }
        var items: [String: Item] = [:]
        var stack: [any XCUIElementSnapshot] = [root]
        while let node = stack.popLast() {
            if !node.identifier.isEmpty, items[node.identifier] == nil {
                items[node.identifier] = Item(label: node.label, value: node.value as? String, frame: node.frame)
            }
            stack.append(contentsOf: node.children)
        }
        self.items = items
    }

    func exists(_ id: String) -> Bool { items[id] != nil }
    func label(_ id: String) -> String? { items[id]?.label }
    func value(_ id: String) -> String? { items[id]?.value }
    func frame(_ id: String) -> CGRect? { items[id]?.frame }
    var debug: TableDebug? { TableDebug(value("table.debug")) }
}

/// A Mac-side command run for a UI test by the host broker (scripts/lib-host-broker.sh, started
/// by scripts/ui-tests.sh; folder in the runner's `POUNCE_BROKER_DIR`). A process spawned from
/// inside the simulator lives in the simulator's bootstrap namespace and can't reach the Mac's
/// network services, so `pounce-e2e` and `xcrun simctl push` run on the Mac side instead. The
/// test and the broker talk through files (the simulator sees the Mac's file system).
final class HostProcess {
    private let base: String

    /// `kind` is `e2e` (pounce-e2e) or `push` (`xcrun simctl push`).
    init(_ kind: String, _ args: [String]) throws {
        guard let dir = ProcessInfo.processInfo.environment["POUNCE_BROKER_DIR"] else {
            throw XCTSkip("needs the host broker (run through scripts/ui-tests.sh)")
        }
        base = dir + "/" + UUID().uuidString
        try ([kind] + args).joined(separator: "\n").write(toFile: base + ".tmp", atomically: true, encoding: .utf8)
        try FileManager.default.moveItem(atPath: base + ".tmp", toPath: base + ".req")
        let deadline = Date().addingTimeInterval(10)
        // Started (.pid), or refused at once (.exit without a .pid).
        while !FileManager.default.fileExists(atPath: base + ".pid"),
              !FileManager.default.fileExists(atPath: base + ".exit") {
            guard Date() < deadline else { throw HostProcessError.notStarted(kind) }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    enum HostProcessError: Error { case notStarted(String) }

    func output() -> String { (try? String(contentsOfFile: base + ".log", encoding: .utf8)) ?? "" }

    var exitStatus: Int32? {
        (try? String(contentsOfFile: base + ".exit", encoding: .utf8)).flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    /// Waits (up to `timeout`) for the command to finish; its exit status, or -1.
    @discardableResult
    func wait(timeout: TimeInterval = 30) -> Int32 {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let status = exitStatus { return status }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return -1
    }

    func stop() {
        guard exitStatus == nil else { return }
        FileManager.default.createFile(atPath: base + ".kill", contents: nil)
        wait(timeout: 5)
    }
}

/// Turns off XCUITest's "wait for the app to idle" before every query and event (test-only,
/// private XCTest selectors). The table never looks idle to XCUITest while SpriteKit animates,
/// and during each wait the scene barely renders: every animation then takes the whole 15 s
/// wait. Long tap-driven games (MixedSeatsTests, MultiSimTests) poll explicitly instead.
enum Quiescence {
    /// Swaps the waits out and returns a closure that puts the original implementations back;
    /// call it from `addTeardownBlock` so later test classes get XCUITest's idle waits again.
    /// Logs how many of the two selectors were found (0 means XCTest renamed them and the
    /// idle waits stay on).
    @MainActor static func disable() -> () -> Void {
        guard let cls = NSClassFromString("XCUIApplicationProcess") else {
            print("[quiescence] XCUIApplicationProcess not found; idle waits stay on")
            return {}
        }
        let one: @convention(block) (AnyObject, Bool) -> Void = { _, _ in }
        let two: @convention(block) (AnyObject, Bool, Bool) -> Void = { _, _, _ in }
        var saved: [(Method, IMP)] = []
        for (name, block) in [("waitForQuiescenceIncludingAnimationsIdle:", one as Any),
                              ("waitForQuiescenceIncludingAnimationsIdle:isPreEvent:", two as Any)] {
            guard let m = class_getInstanceMethod(cls, NSSelectorFromString(name)) else { continue }
            saved.append((m, method_setImplementation(m, imp_implementationWithBlock(block))))
        }
        print("[quiescence] idle waits off (\(saved.count) of 2 selectors found)")
        XCTAssertFalse(saved.isEmpty, "no XCUITest quiescence selector found; idle waits stay on")
        return {
            for (m, imp) in saved { method_setImplementation(m, imp) }
            print("[quiescence] idle waits restored")
        }
    }
}
