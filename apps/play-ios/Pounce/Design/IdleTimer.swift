import UIKit

/// The system's idle timer (`UIApplication.isIdleTimerDisabled`), held off by whoever needs the
/// screen on (`KeepAwake` decides when): a table, by its room code. Off while anyone holds it.
/// Main thread, one property write, and only when the answer changes.
@MainActor
enum IdleTimer {
    private static var holders: Set<String> = []

    /// `on`: `holder` needs the screen kept on (true) or no longer does (false).
    static func keepAwake(_ on: Bool, for holder: String) {
        if on { holders.insert(holder) } else { holders.remove(holder) }
        let off = !holders.isEmpty
        if UIApplication.shared.isIdleTimerDisabled != off { UIApplication.shared.isIdleTimerDisabled = off }
    }

    #if DEBUG
    /// For the UI tests' probes: the timer is held off.
    static var isHeldOff: Bool { !holders.isEmpty }
    #endif
}
