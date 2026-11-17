import notify
import XCTest

/// The Apple TV UI tests' launch settings and waits: the iPhone's `Live` (`PounceUITests`), less
/// what needs a touch screen or a server. Every TV test runs on a `-demo` (no server).
@MainActor
enum Live {
    /// The app's speed under test: `POUNCE_SPEED` in the runner's environment
    /// (`TEST_RUNNER_POUNCE_SPEED`), default 10; 1 is normal speed.
    nonisolated static let speed: Double = {
        let raw = ProcessInfo.processInfo.environment["POUNCE_SPEED"].flatMap(Double.init) ?? 10
        return raw > 0 ? raw : 1
    }()

    /// A fixed wait of `seconds` at normal speed, at the test speed (never under `floor`).
    nonisolated static func pace(_ seconds: TimeInterval, floor: TimeInterval = 0.1) -> TimeInterval {
        max(seconds / speed, min(floor, seconds))
    }

    /// A poll interval, floored at 0.25 s: every poll snapshots the app's accessibility tree on its
    /// main thread.
    nonisolated static func poll(_ seconds: TimeInterval) -> TimeInterval { pace(seconds, floor: 0.25) }

    /// Every test app's arguments: its speed, and `-watchdog` (`Watchdog`).
    nonisolated static func arguments(speed: Double = speed) -> [String] {
        ["-anim-speed", String(speed), "-watchdog"]
    }

    /// The TV on a `-demo` (`TVDemo`): `tv-hit`, `tv-tiles` or `tv-shell`.
    static func demo(_ name: String, speed: Double = speed) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments(speed: speed) + ["-demo", name]
        return app
    }

    /// The demo's next step (`TVDemoSignal.release`): the lobby's seats fill, then the game starts.
    nonisolated static func releaseDemo() {
        notify_post("com.conleychaos.play.demo.release")
    }

    /// Ends the demo's game (`TVDemoSignal.end`).
    nonisolated static func endDemo() {
        notify_post("com.conleychaos.play.demo.end")
    }

    /// Multiplies every timeout (`POUNCE_UITEST_TIMEOUT_SCALE`, `TEST_RUNNER_…` for xcodebuild).
    nonisolated static let scale: Double = {
        let raw = ProcessInfo.processInfo.environment["POUNCE_UITEST_TIMEOUT_SCALE"].flatMap(Double.init) ?? 1
        return raw > 0 ? raw : 1
    }()

    nonisolated static func t(_ seconds: TimeInterval) -> TimeInterval { seconds * scale }
}

@MainActor
extension XCTestCase {
    func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    /// Polls `condition` every 0.5 s (at the test speed) until it holds or `timeout` (scaled)
    /// passes.
    @discardableResult
    func until(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(Live.t(timeout))
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: Live.poll(0.5))
        }
        return condition()
    }

    /// The element's value, or nil if it isn't there.
    func value(_ e: XCUIElement) -> String? {
        (try? e.snapshot())?.value as? String
    }

    /// The element's label, or nil if it isn't there.
    func label(_ e: XCUIElement) -> String? {
        (try? e.snapshot())?.label
    }

    // MARK: the remote

    /// The identifier of the element the remote's focus is on (empty for one without), or nil when
    /// nothing has the focus. One snapshot of the app.
    func focusedID(_ app: XCUIApplication) -> String? {
        guard let root = try? app.snapshot() else { return nil }
        var stack: [any XCUIElementSnapshot] = [root]
        while let node = stack.popLast() {
            if node.hasFocus { return node.identifier }
            stack.append(contentsOf: node.children)
        }
        return nil
    }

    /// Waits until the element `id` has the remote's focus.
    @discardableResult
    func waitForFocus(_ app: XCUIApplication, _ id: String, timeout: TimeInterval = 5) -> Bool {
        until(timeout) { self.focusedID(app) == id }
    }

    /// Presses a button on the Siri Remote, and checks that something still has the focus after
    /// it (Select and Menu must always have somewhere to go). Returns what has it.
    @discardableResult
    func press(_ app: XCUIApplication, _ button: XCUIRemote.Button, forDuration seconds: TimeInterval? = nil,
               file: StaticString = #filePath, line: UInt = #line) -> String? {
        if let seconds {
            XCUIRemote.shared.press(button, forDuration: seconds)
        } else {
            XCUIRemote.shared.press(button)
        }
        var focus: String?
        let held = until(3) {
            focus = self.focusedID(app)
            return focus != nil
        }
        XCTAssertTrue(held, "nothing has the focus after pressing \(Self.name(button))", file: file, line: line)
        return focus
    }

    private static func name(_ button: XCUIRemote.Button) -> String {
        switch button {
        case .up: "Up"
        case .down: "Down"
        case .left: "Left"
        case .right: "Right"
        case .select: "Select"
        case .menu: "Menu"
        case .playPause: "Play/Pause"
        case .home: "Home"
        default: "button \(button.rawValue)"
        }
    }
}
