import CoreGraphics
import Testing
@testable import PounceKit

/// Which laid group a dragged card is over, and which end of it.
@Suite struct LaidTargetsTests {
    private let a = HitTarget(seat: 1, group: 0)
    private let b = HitTarget(seat: 1, group: 1)
    private let c = HitTarget(seat: 2, group: 0)

    /// Two groups side by side (8 pt apart) and one row 8 pt below, as `LaidZoneNode` draws
    /// them; mini cards 41 x 58.
    private var frames: [(target: HitTarget, frame: CGRect)] {
        [
            (a, CGRect(x: 40, y: 100, width: 80, height: 58)),
            (b, CGRect(x: 128, y: 100, width: 60, height: 58)),
            (c, CGRect(x: 40, y: 34, width: 100, height: 58)),
        ]
    }

    /// JD's bug: a drop in the strip between two rows went to the row listed first, even with
    /// the finger nearer the other one. The nearest group wins.
    @Test func theNearestGroupWinsBetweenRows() {
        #expect(LaidTargets.target(at: CGPoint(x: 60, y: 95), in: frames) == c)   // 3 pt off c, 5 off a
        #expect(LaidTargets.target(at: CGPoint(x: 60, y: 97), in: frames) == a)   // 3 off a, 5 off c
        #expect(LaidTargets.target(at: CGPoint(x: 125, y: 120), in: frames) == b) // 3 off b, 5 off a
        #expect(LaidTargets.target(at: CGPoint(x: 123, y: 120), in: frames) == a)
    }

    @Test func aFingerOnAGroupAlwaysPicksIt() {
        for (target, f) in frames {
            for p in [CGPoint(x: f.minX + 1, y: f.minY + 1), CGPoint(x: f.midX, y: f.midY), CGPoint(x: f.maxX - 1, y: f.maxY - 1)] {
                #expect(LaidTargets.target(at: p, in: frames) == target)
            }
        }
    }

    /// Generous on the smallest phone: a finger up to `reach` past a group's edge still takes it.
    @Test func reachIsGenerousButBounded() {
        #expect(LaidTargets.reach >= 14)
        #expect(LaidTargets.target(at: CGPoint(x: 40 - 13, y: 120), in: frames) == a)
        #expect(LaidTargets.target(at: CGPoint(x: 80, y: 158 + 13), in: frames) == a)
        #expect(LaidTargets.target(at: CGPoint(x: 80, y: 158 + LaidTargets.reach + 1), in: frames) == nil)
        #expect(LaidTargets.target(at: CGPoint(x: 300, y: 120), in: frames) == nil)
        #expect(LaidTargets.target(at: .zero, in: []) == nil)
    }

    @Test func theHalfOfTheGroupPicksTheEnd() {
        let f = CGRect(x: 40, y: 100, width: 80, height: 58)
        #expect(LaidTargets.side(at: CGPoint(x: 41, y: 120), of: f) == .start)
        #expect(LaidTargets.side(at: CGPoint(x: 79, y: 120), of: f) == .start)
        #expect(LaidTargets.side(at: CGPoint(x: 81, y: 120), of: f) == .end)
        #expect(LaidTargets.side(at: CGPoint(x: 20, y: 120), of: f) == .start)  // past the left edge
        #expect(LaidTargets.side(at: CGPoint(x: 140, y: 120), of: f) == .end)
    }
}
