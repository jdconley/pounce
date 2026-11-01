import Foundation

/// Timings for the table's big moments (spec §5.10, §9.1), free of SpriteKit so the round-over
/// budget can be tested. The server starts the next round 6 s after `roundOver`, so the whole
/// round-over sequence (points pop, then every shelf leap) must fit in `roundOverBudget`; the
/// staggers shrink when many seats score or leap.
public enum CelebrationTiming {
    /// The round-over sequence never runs longer than this (seconds).
    public static let roundOverBudget: TimeInterval = 5

    /// Versus intro before the first deal: cats slide in on color slashes.
    public static let versusIntro: TimeInterval = 1.2

    // Points pop: an outlined "+N" pops off each cat in seat order.
    public static let pointsStaggerMax: TimeInterval = 0.3
    public static let pop: TimeInterval = 0.22
    /// The numeral's float and fade after it popped (runs on in the background).
    public static let pointsTail: TimeInterval = 0.7
    /// A breath between the last points pop and the first leap.
    public static let beforeLeaps: TimeInterval = 0.25

    // Shelf leap: squat, arc, squash land, star burst and the shelf badge pop.
    public static let leapStaggerMax: TimeInterval = 0.45
    public static let squat: TimeInterval = 0.08
    public static let arc: TimeInterval = 0.35
    public static let squash: TimeInterval = 0.14
    public static let badgeHold: TimeInterval = 0.3
    public static var leap: TimeInterval { squat + arc + squash + pop + badgeHold }

    /// The table zooms onto the tower for the leaps, and back.
    public static let zoomIn: TimeInterval = 0.35
    public static let zoomOut: TimeInterval = 0.3

    // Game over.
    /// The sunburst turns once, slowly, then stops (the view may pause again).
    public static let sunburstLoop: TimeInterval = 4
    public static let crownDrop: TimeInterval = 0.45

    /// Gap between two seats' points pops.
    public static func pointsStagger(seats: Int) -> TimeInterval {
        seats > 1 ? min(pointsStaggerMax, 1.2 / Double(seats - 1)) : 0
    }

    /// Gap between two cats' leaps.
    public static func leapStagger(leapers: Int) -> TimeInterval {
        leapers > 1 ? min(leapStaggerMax, 1.35 / Double(leapers - 1)) : 0
    }

    /// When the first leap starts, from the start of the sequence.
    public static func leapsStart(seats: Int) -> TimeInterval {
        Double(max(seats - 1, 0)) * pointsStagger(seats: seats) + pop + beforeLeaps + zoomIn
    }

    /// The whole round-over sequence. `finale` (a `gameOver` follows) keeps the zoom for the
    /// game-over moment instead of zooming back out.
    public static func roundOver(seats: Int, leapers: Int, finale: Bool = false) -> TimeInterval {
        let points = Double(max(seats - 1, 0)) * pointsStagger(seats: seats) + pop
        guard leapers > 0 else { return points + pointsTail }
        return leapsStart(seats: seats) + Double(leapers - 1) * leapStagger(leapers: leapers) + leap
            + (finale ? 0 : zoomOut)
    }
}
