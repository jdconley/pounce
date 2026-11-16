import Foundation
#if DEBUG
import OSLog
import QuartzCore
#endif

/// Times a piece of a frame's main-thread work (`docs/main-thread.md`): a redraw, a reconcile, a
/// touch, an accessibility rebuild. In Debug builds it is a signpost interval (Instruments' Points
/// of Interest) and, under `-watchdog`, a note the watchdog prints next to any slow frame it
/// happened in. In Release it does nothing. Use it as the first line of the work:
///
///     let work = FrameWork("tiles.redraw"); defer { work.end() }
///
/// Times are the main thread's CPU time, not the wall clock: a busy Mac that holds the simulator
/// up mid-redraw doesn't count against the app.
///
/// `read: true` marks work an accessibility read asks for (VoiceOver, or a UI test's query): it
/// is timed and reported apart, not counted in the frame it lands in.
@MainActor
struct FrameWork {
    #if DEBUG
    private let name: StaticString
    private let state: OSSignpostIntervalState
    private let start: CFTimeInterval
    private let read: Bool
    private static let signposter = OSSignposter(subsystem: "com.conleychaos.play", category: .pointsOfInterest)
    /// Pieces open now: only the outermost one counts toward a frame's total.
    private static var depth = 0

    /// This thread's CPU time so far, in seconds.
    private static func cpuNow() -> CFTimeInterval {
        Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) / 1e9
    }
    #endif

    @inline(__always)
    init(_ name: StaticString, read: Bool = false) {
        #if DEBUG
        self.name = name
        self.read = read
        state = Self.signposter.beginInterval(name)
        start = Self.cpuNow()
        Self.depth += 1
        #endif
    }

    @inline(__always)
    func end() {
        #if DEBUG
        Self.signposter.endInterval(name, state)
        Self.depth -= 1
        MainThreadWatchdog.shared?.noteWork(name, ms: (Self.cpuNow() - start) * 1000, outermost: Self.depth == 0, read: read)
        #endif
    }
}
