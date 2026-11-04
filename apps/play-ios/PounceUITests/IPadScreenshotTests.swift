import XCTest

/// Screenshots in both orientations, for the iPad art folder (`Art/screenshots/ipad/`). iPadOS
/// refuses an app's own orientation requests in its windowing modes, so only a UI test can turn
/// the simulator. Skipped unless the runner's environment names a folder:
///
///     TEST_RUNNER_POUNCE_SHOTS_DIR=/some/dir \
///     TEST_RUNNER_POUNCE_SHOTS='table=-demo table;join=-show-join' \
///     xcodebuild test ... -only-testing:PounceUITests/IPadScreenshotTests
///
/// `POUNCE_SHOTS` is `name=launch args` entries split by `;` (default: the table demos);
/// `POUNCE_SHOTS_ORIENTATIONS` is `portrait,landscape` by default; `POUNCE_SHOTS_WAIT` the
/// seconds to let a screen settle (default 5). Each shot lands as `<name>-<orientation>.png`.
/// Runs at normal speed so screens show their resting state, not a sped-up animation.
@MainActor
final class IPadScreenshotTests: XCTestCase {
    func testCaptureScreens() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["POUNCE_SHOTS_DIR"], !dir.isEmpty else {
            throw XCTSkip("no POUNCE_SHOTS_DIR")
        }
        let spec = env["POUNCE_SHOTS"]
            ?? "table=-demo table;crowded=-demo crowded;other=-demo other;hit=-demo hit;curtain=-demo curtain"
        let orientations = (env["POUNCE_SHOTS_ORIENTATIONS"] ?? "portrait,landscape").split(separator: ",").map(String.init)
        let wait = env["POUNCE_SHOTS_WAIT"].flatMap(Double.init) ?? 5
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for entry in spec.split(separator: ";") {
            let parts = entry.split(separator: "=", maxSplits: 1).map(String.init)
            guard let name = parts.first, !name.isEmpty else { continue }
            let args = parts.count > 1 ? parts[1].split(separator: " ").map(String.init) : []
            for orientation in orientations {
                XCUIDevice.shared.orientation = orientation == "landscape" ? .landscapeLeft : .portrait
                let app = XCUIApplication()
                app.launchArguments = Live.arguments(speed: 1) + args
                app.launch()
                Thread.sleep(forTimeInterval: wait)
                let png = XCUIScreen.main.screenshot().pngRepresentation
                try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name)-\(orientation).png"))
                app.terminate()
            }
        }
        XCUIDevice.shared.orientation = .portrait
    }
}
