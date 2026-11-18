#if DEBUG
import Foundation

// The table's DEBUG timeline: the iPhone's `-demo` tables (`DemoMode`) and `-log-timeline` print
// one line per game intent. Here, with the table, so every app that draws a table has it.

extension TableScene {
    #if os(iOS)
    private static let logsTimeline = [.replay, .nope, .celebrate, .handoff].contains(DemoMode.from())
    #else
    /// The Apple TV has no demo tables (`DemoMode` is the iPhone app's).
    private static let logsTimeline = false
    #endif
    /// `-log-timeline` (any table, e.g. a UI test against the dev server): the same lines to the
    /// unified log (`log stream --predicate 'eventMessage CONTAINS "[timeline]"'`).
    static let logsTimelineToSystem = CommandLine.arguments.contains("-log-timeline")

    /// `-demo replay`: one line per game intent (played with its duration, or skipped).
    func timelineLog(_ line: @autoclosure () -> String) {
        if Self.logsTimeline { print("[timeline] \(line())") }
        if Self.logsTimelineToSystem { NSLog("[timeline] %@", line()) }
    }

    /// `-demo replay`: prints the rendered frame count once a second (a Task, so it never
    /// wakes the view itself).
    func startFrameLog() {
        let director = director
        let clock = ContinuousClock()
        let start = clock.now
        Task { [weak self] in
            var last = director.framesRendered
            while self != nil {
                try? await Task.sleep(for: .seconds(1))
                let frames = director.framesRendered
                let t = (clock.now - start).components.seconds
                print("[replay] t=\(t)s frames=\(frames) +\(frames - last) paused=\(self?.view?.isPaused ?? true)")
                last = frames
            }
        }
    }
}
#endif
