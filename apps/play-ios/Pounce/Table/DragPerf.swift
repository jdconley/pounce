#if DEBUG
import Foundation
import CoreGraphics
import QuartzCore

/// DEBUG drag profiler: while a card is dragged, how long each touch move takes on the main
/// thread, the gaps between rendered frames, and how often the hit rules ran. Printed as one
/// `[dragperf]` line when the drag ends, for before and after numbers on a busy table.
struct DragPerf {
    private var moveTimes: [Double] = []
    private var frameGaps: [Double] = []
    private var lastFrame: Double?
    /// Per frame: how far the drawn card is from where the finger puts it (points).
    private var trail: [Double] = []
    /// Where the finger puts the dragged card now (under it, or lifted above a laid group).
    var intended: CGPoint?
    /// `TableModel.hitPlan` / `hitTargets` calls made by the drag (the move path and redraws).
    var hitRuleCalls = 0
    /// Laid-zone preview rebuilds (`setPreview` that changed something).
    var previewChanges = 0

    mutating func begin() {
        self = DragPerf()
    }

    mutating func move(_ seconds: Double) { moveTimes.append(seconds * 1000) }

    mutating func frame(_ time: TimeInterval, drawn: CGPoint?) {
        if let drawn, let intended { trail.append(Double(hypot(drawn.x - intended.x, drawn.y - intended.y))) }
        if let lastFrame { frameGaps.append((time - lastFrame) * 1000) }
        lastFrame = time
    }

    var summary: String {
        func stats(_ xs: [Double], _ unit: String = "ms") -> String {
            guard !xs.isEmpty else { return "n=0" }
            let s = xs.sorted()
            let avg = s.reduce(0, +) / Double(s.count)
            let p95 = s[min(s.count - 1, Int(Double(s.count) * 0.95))]
            return String(format: "n=%d avg=%.2f%@ p95=%.2f%@ max=%.2f%@", s.count, avg, unit, p95, unit, s.last!, unit)
        }
        let trailing = trail.filter { $0 > 4 }.count
        let long = frameGaps.filter { $0 > 1000 / 60 * 1.5 }.count
        return "[dragperf] moves(\(stats(moveTimes))) frames(\(stats(frameGaps)) over25ms=\(long)) trail(\(stats(trail, "pt")) over4pt=\(trailing)) hitRules=\(hitRuleCalls) previews=\(previewChanges)"
    }
}
#endif
