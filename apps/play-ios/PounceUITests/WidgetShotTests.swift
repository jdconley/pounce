import XCTest

/// Screenshots of the widgets on the real Home Screen and Lock Screen (spec §11.1), from the demo
/// pairs `-demo-streaks` writes to the App Group. Drives SpringBoard: it adds the Us widget (small
/// and medium) to the Home Screen and the Streak widget (circular, rectangular, inline) to the
/// Lock Screen. Skipped unless the runner's environment names a folder:
///
///     TEST_RUNNER_POUNCE_SHOTS_DIR=/some/dir xcodebuild test ... -only-testing:PounceUITests/WidgetShotTests
///
/// `POUNCE_SHOTS_ORIENTATIONS=landscape` turns the device first. Shots land as
/// `home-<orientation>.png` and `lock-<orientation>.png`; with `POUNCE_SHOTS_DUMP=1` each step also
/// writes SpringBoard's element tree beside them (for when iOS moves a button).
@MainActor
final class WidgetShotTests: XCTestCase {
    private var dir = ""
    private var orientation = "portrait"
    private var dump = false
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["POUNCE_SHOTS_DIR"], !dir.isEmpty else { throw XCTSkip("no POUNCE_SHOTS_DIR") }
        self.dir = dir
        orientation = env["POUNCE_SHOTS_ORIENTATIONS"] == "landscape" ? "landscape" : "portrait"
        dump = env["POUNCE_SHOTS_DUMP"] == "1"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        continueAfterFailure = false
    }

    /// The demo pairs into the App Group, then back to the Home Screen.
    private func writeSnapshot() {
        let app = XCUIApplication()
        app.launchArguments = Live.arguments(speed: 10) + ["-uitest-reset", "-seed-people", "-demo-streaks"]
        app.launch()
        XCTAssertTrue(el(app, "home.streak").waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 1)
        XCUIDevice.shared.press(.home)
        XCUIDevice.shared.orientation = orientation == "landscape" ? .landscapeLeft : .portrait
        Thread.sleep(forTimeInterval: 1)
    }

    private func step(_ name: String) {
        guard dump else { return }
        try? springboard.debugDescription.write(
            toFile: "\(dir)/sb-\(orientation)-\(name).txt", atomically: true, encoding: .utf8)
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent("sb-\(orientation)-\(name).png"))
    }

    private func shot(_ name: String) throws {
        Thread.sleep(forTimeInterval: 2)
        try XCUIScreen.main.screenshot().pngRepresentation
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name)-\(orientation).png"))
    }

    private func any(_ label: String) -> XCUIElement {
        springboard.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func containing(_ text: String) -> XCUIElement {
        springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Opens the widget gallery, finds Pounce, and adds the widget on gallery page `page`.
    private func addHomeWidget(page: Int) throws {
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).press(forDuration: 1.5)
        step("jiggle")
        let edit = springboard.buttons["Edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "no Edit")
        edit.tap()
        step("edit-menu")
        let add = any("Add Widget")
        XCTAssertTrue(add.waitForExistence(timeout: 5), "no Add Widget")
        add.tap()
        step("gallery")
        let search = springboard.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "no gallery search")
        search.tap()
        search.typeText("Pounce")
        step("search")
        let result = springboard.cells.containing(NSPredicate(format: "label CONTAINS 'Pounce'")).firstMatch
        let row = result.exists ? result : containing("Pounce")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "no Pounce in the gallery")
        row.tap()
        step("pounce-gallery")
        let preview = springboard.buttons.matching(NSPredicate(format: "label == 'Pounce, Us'")).firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 5), "no Us preview")
        for _ in 0..<page {
            preview.swipeLeft()
            Thread.sleep(forTimeInterval: 1)
        }
        step("pounce-page-\(page)")
        let addButton = springboard.buttons.matching(NSPredicate(format: "label CONTAINS 'Add Widget'")).firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 5), "no Add Widget button in the gallery")
        addButton.tap()
        Thread.sleep(forTimeInterval: 1.5)
        step("added-\(page)")
        let done = springboard.buttons["Done"]
        if done.waitForExistence(timeout: 3) { done.tap() }
        Thread.sleep(forTimeInterval: 1)
    }

    /// Locks the device (XCUIDevice has no public lock button).
    private func lock() {
        XCUIDevice.shared.perform(NSSelectorFromString("pressLockButton"))
        Thread.sleep(forTimeInterval: 1.5)
    }

    /// Wakes the Lock Screen without unlocking it.
    private func wake() {
        XCUIDevice.shared.perform(NSSelectorFromString("pressLockButton"))
        Thread.sleep(forTimeInterval: 1.5)
    }

    func testLockScreenWidgets() throws {
        writeSnapshot()
        lock()
        wake()
        step("lock")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.5)
        step("lock-press")
        let customize = any("Customize")
        XCTAssertTrue(customize.waitForExistence(timeout: 5), "no Customize")
        customize.tap()
        step("customize")
        let lockScreen = containing("Lock Screen")
        if lockScreen.waitForExistence(timeout: 3) { lockScreen.tap() }
        step("lock-editor")
        // iPad explains that each orientation has its own widgets, once.
        let ok = springboard.buttons["OK"]
        if ok.waitForExistence(timeout: 2) {
            ok.tap()
            Thread.sleep(forTimeInterval: 1.5)
        }
        let addWidgets = containing("Add Widget")
        XCTAssertTrue(addWidgets.waitForExistence(timeout: 5), "no Add Widgets on the Lock Screen")
        // The app list opens as a sheet of cells; a tap during an animation can miss.
        for _ in 0..<3 where springboard.cells.count < 3 {
            addWidgets.tap()
            Thread.sleep(forTimeInterval: 1.5)
        }
        step("lock-gallery")
        // The half-height sheet lists apps alphabetically: open it up, then scroll to Pounce.
        let grabber = any("Sheet Grabber")
        if grabber.waitForExistence(timeout: 3) {
            grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)))
            Thread.sleep(forTimeInterval: 1)
        }
        let pounce = springboard.cells["Pounce"]
        for _ in 0..<6 where !(pounce.exists && pounce.isHittable) {
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
                .press(forDuration: 0.05, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
            Thread.sleep(forTimeInterval: 0.8)
        }
        step("lock-gallery-scrolled")
        XCTAssertTrue(pounce.waitForExistence(timeout: 5), "no Pounce in the Lock Screen gallery")
        pounce.tap()
        step("lock-pounce")
        // Each family the Streak widget offers, as the gallery lists them.
        let tiles = springboard.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Pounce, Streak'"))
        for i in 0..<tiles.count { tiles.element(boundBy: i).tap(); Thread.sleep(forTimeInterval: 0.5) }
        step("lock-added")
        let close = any("Close")
        if close.exists { close.tap() } else { any("close").tap() }
        Thread.sleep(forTimeInterval: 1)
        // The app list is still up: down it goes, then the date line takes the inline widget.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
        Thread.sleep(forTimeInterval: 1)
        step("lock-closed")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.085)).tap()
        Thread.sleep(forTimeInterval: 1)
        step("inline-gallery")
        let inline = springboard.cells.matching(NSPredicate(format: "label BEGINSWITH 'Pounce, Streak'")).firstMatch
        for _ in 0..<6 where !(inline.exists && inline.isHittable) {
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
                .press(forDuration: 0.05, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)))
            Thread.sleep(forTimeInterval: 0.8)
        }
        step("inline-scrolled")
        if inline.exists {
            inline.tap()
            Thread.sleep(forTimeInterval: 1)
        }
        step("inline-added")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
        Thread.sleep(forTimeInterval: 1)
        step("inline-closed")
        let done = springboard.buttons["editing-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 3), "no Done")
        done.tap()
        Thread.sleep(forTimeInterval: 1.5)
        step("lock-done")
        // Back from the wallpaper carousel to the Lock Screen.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        Thread.sleep(forTimeInterval: 1)
        // Back to the Lock Screen itself.
        lock()
        wake()
        try shot("lock")
        XCUIDevice.shared.orientation = .portrait
    }

    /// The Home Screen as it is (widgets added by an earlier run), turned to the orientation.
    func testHomeScreenAsIs() throws {
        guard ProcessInfo.processInfo.environment["POUNCE_SHOTS_AS_IS"] == "1" else { throw XCTSkip("POUNCE_SHOTS_AS_IS unset") }
        writeSnapshot()
        try shot("home")
        XCUIDevice.shared.orientation = .portrait
    }

    func testHomeScreenWidgets() throws {
        guard ProcessInfo.processInfo.environment["POUNCE_SHOTS_AS_IS"] != "1" else { throw XCTSkip("as-is run") }
        writeSnapshot()
        try addHomeWidget(page: 1)  // medium
        try addHomeWidget(page: 0)  // small
        try shot("home")
        XCUIDevice.shared.orientation = .portrait
    }
}
