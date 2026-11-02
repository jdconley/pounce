import PounceKit
import SwiftUI

/// The app's one speed knob, DEBUG only (Release always runs at 1). Every wait a game goes
/// through runs at `factor` times normal speed: the table scene's speed, shell animations
/// (`.paced`), keyframes and paced sleeps (`Pace.seconds`, `Pace.duration`), and UIKit
/// animations (sheets) through the window's layer speed.
///
/// `-anim-speed <n>` or `POUNCE_ANIM_SPEED` sets it (the UI test scripts' `SPEED`, default 10);
/// either one also makes this a test run, where sound and haptics go silent. `-slowmo <f>`
/// (f ≤ 1) is the demo screenshots' slow motion. See `PaceSetting`.
enum Pace {
    #if DEBUG
    private static let resolved = PaceSetting.resolve(
        arguments: CommandLine.arguments, env: ProcessInfo.processInfo.environment)
    static let factor = resolved.factor
    /// A UI test launched the app (`-anim-speed` / `POUNCE_ANIM_SPEED`, at any speed).
    static let underTest = resolved.underTest
    #else
    static let factor = 1.0
    static let underTest = false
    #endif

    /// `seconds` of normal-speed time at this pace.
    static func seconds(_ seconds: Double) -> Double { seconds / factor }

    /// `duration` of normal-speed time at this pace.
    static func duration(_ duration: Duration) -> Duration { duration / factor }

    /// Speeds up the app windows' Core Animation clocks (UIKit sheet presentations, the share
    /// sheet, alerts). SwiftUI animations are scaled by `.paced` instead, the table by its scene
    /// speed.
    @MainActor static func applyToWindows() {
        guard factor != 1 else { return }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows { window.layer.speed = Float(factor) }
        }
    }
}

extension Animation {
    /// This animation at the app's pace (`Pace.factor`).
    var paced: Animation { speed(Pace.factor) }
}
